local ADDON, ns = ...

local applyingColor = false

local ok = ns.Ok
local fail = ns.Fail
local note = ns.Note
local plural = ns.Plural

local function trim(s)
    return (s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

-- A cooldown duration is a number with an optional unit: bare numbers are minutes, s m h d spell the rest. Zero and malformed input return nil so the caller can name the slip.
local DURATION_UNITS = { s = 1, m = 60, h = 3600, d = 86400 }
local DURATION_HINT = "Use 30 (minutes), 30m, 2h or 30d."

local function parseDuration(token)
    local amount, unit = token:match("^(%d+%.?%d*)([smhdSMHD]?)$")
    if not amount then return nil end
    local seconds = tonumber(amount) * DURATION_UNITS[unit == "" and "m" or unit:lower()]
    if not seconds or seconds <= 0 then return nil end
    return math.floor(seconds)
end

local function loadBlocked()
    SuperSocialDB = SuperSocialDB or {}

    -- Permanent, account-wide block list: keys are lowercased names so lookups ignore capitalization, values keep the name as shown in chat.
    local bucket = SuperSocialDB.blockedAccount or {}
    SuperSocialDB.blockedAccount = bucket
    return bucket
end

local function loadCooldowns()
    SuperSocialDB = SuperSocialDB or {}

    -- One account-wide cooldown list shared by every character, so a relog onto an alt keeps everyone's cooldown running. Keys are lowercased names, values the time the cooldown expires, so one list serves a 30-minute and a 30-day cooldown alike.
    local bucket = SuperSocialDB.cooldownAccount or {}
    SuperSocialDB.cooldownAccount = bucket

    -- Expired entries go on every load so the list can't grow without bound; a non-number is pre-migration debris and goes too.
    local now = time()
    for name, expiry in pairs(bucket) do
        if type(expiry) ~= "number" or expiry <= now then bucket[name] = nil end
    end
    return bucket
end

local function clearCooldowns()
    wipe(loadCooldowns())
end

local function nameOnly(value)
    if not value then return nil end
    return value:match("^([^-]+)") or value
end

-- Matches both "Name" and "Name-Realm" forms against the lowercased keys.
local function isBlocked(blocked, fullName)
    if blocked[fullName:lower()] then return true end
    local short = nameOnly(fullName)
    return short ~= fullName and blocked[short:lower()] or false
end

-- The cooldown list needs the same two-form lookup, so a hand-added short name still catches the player's "Name-Realm" form in a /who.
local function onCooldown(cooldowns, fullName)
    local now = time()
    local expiry = cooldowns[fullName:lower()]
    if expiry and expiry > now then return true end
    local short = nameOnly(fullName)
    if short == fullName then return false end
    expiry = cooldowns[short:lower()]
    return expiry ~= nil and expiry > now
end

local function buildGroupSet()
    local set = {}
    local me = UnitName("player")
    if me then set[me] = true end
    if not IsInGroup() then return set end
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local n = UnitName("raid" .. i)
            if n then set[n] = true end
        end
    else
        for i = 1, 4 do
            local n = UnitName("party" .. i)
            if n then set[n] = true end
        end
    end
    return set
end

-- People who left the group (or the whole group on disband) still count as groupmates for the /ww and /rr skip checks for a while afterwards. The watcher diffs the roster on every change and stamps whoever vanished. Session-only, like the reply tracking.
local RECENT_GROUP_SECONDS = 15 * 60
local leftGroupAt = {}  -- short name -> time they left the group
local lastRoster = {}

local rosterWatcher = CreateFrame("Frame")
rosterWatcher:RegisterEvent("GROUP_ROSTER_UPDATE")
rosterWatcher:RegisterEvent("PLAYER_ENTERING_WORLD")
rosterWatcher:SetScript("OnEvent", function()
    local roster = buildGroupSet()
    for name in pairs(lastRoster) do
        if not roster[name] then
            leftGroupAt[name] = time()
        end
    end
    lastRoster = roster
    -- Sweep expired leavers on the same event, so the table can't grow all session between checks.
    local cutoff = time() - RECENT_GROUP_SECONDS
    for name, at in pairs(leftGroupAt) do
        if at < cutoff then leftGroupAt[name] = nil end
    end
end)

local function wasRecentlyGrouped(short)
    local leftAt = leftGroupAt[short]
    if not leftAt then return false end
    if (time() - leftAt) >= RECENT_GROUP_SECONDS then
        leftGroupAt[short] = nil
        return false
    end
    return true
end

ns.NameOnly = nameOnly
ns.BuildGroupSet = buildGroupSet
ns.WasRecentlyGrouped = wasRecentlyGrouped

local function whisperTarget(input)
    input = trim(input or "")
    local tokens = {}
    for t in input:gmatch("%S+") do tokens[#tokens + 1] = t end
    local cursor = 1
    local cooldownSeconds
    if tokens[cursor] == "-cd" then
        cooldownSeconds = tokens[cursor + 1] and parseDuration(tokens[cursor + 1])
        if not cooldownSeconds then
            fail("-cd needs a duration.", DURATION_HINT)
            return
        end
        cursor = cursor + 2
    end
    local parts = ns.SplitWhisper(table.concat(tokens, " ", cursor))
    if #parts == 0 then
        note("Usage: /wt MESSAGE whispers your target, e.g. /wt got room for one more? Add -cd 30d to put them on cooldown.")
        return
    end
    if not (UnitExists("target") and UnitIsPlayer("target")) then
        fail("No target selected.", "Pick a player first.")
        return
    end
    local targetName = UnitName("target")
    if isBlocked(loadBlocked(), targetName) then
        fail("Blocked.", targetName .. " is on the block list (/ss -unblock " .. targetName .. ").")
        return
    end
    -- Through the queue for cap rescue, flagged personal so /rr treats it as an answer, not a blast.
    for _, part in ipairs(parts) do
        ns.QueueWhisper(part, targetName, "personal")
    end
    if cooldownSeconds then
        loadCooldowns()[targetName:lower()] = time() + cooldownSeconds
        ok("Whispered", targetName .. ", " .. ns.FormatDuration(cooldownSeconds) .. " cooldown.")
    else
        ok("Whispered", targetName .. ".")
    end
end

-- Every flag parseFlags understands, used to catch one misplaced after the message.
local FLAG_WORDS = { ["-limit"] = true, ["-skip"] = true, ["-only"] = true, ["-cd"] = true, ["-who"] = true }

-- Flags whose value is a bracket group, mapped to the opts field the group fills.
local BRACKET_FLAGS = { ["-who"] = "who", ["-skip"] = "terms", ["-only"] = "includeTerms" }

-- A bracket flag may arrive glued to its opening bracket, so "-skip(mage)" still names the flag.
local function flagName(token)
    return token:match("^(%-%a+)%(") or token
end

-- A bracket group starts right after its flag and runs to the first closing bracket, so the message may start with anything and the boundary is never guessed. Text glued behind the closing bracket becomes the next token. Returns the content and the cursor past it, or nil, the mistake and the cursor.
local function readBracket(tokens, cursor, flag)
    local head = tokens[cursor]:sub(#flag + 1)
    if head == "" then
        cursor = cursor + 1
        head = tokens[cursor]
    end
    if not head or head:sub(1, 1) ~= "(" then return nil, "open", cursor end
    local parts = {}
    local piece = head:sub(2)
    while true do
        local body, rest = piece:match("^(.-)%)(.*)$")
        if body then
            parts[#parts + 1] = body
            if rest ~= "" then tokens[cursor] = rest else cursor = cursor + 1 end
            local content = trim(table.concat(parts, " "))
            if content == "" then return nil, "empty", cursor end
            return content, nil, cursor
        end
        parts[#parts + 1] = piece
        cursor = cursor + 1
        piece = tokens[cursor]
        if not piece then return nil, "close", cursor end
    end
end

-- Field keys inside -skip and -only brackets, the same letters /who uses so one vocabulary serves both.
local TERM_FIELDS = { c = "class", z = "zone", n = "name" }

-- Split a bracket group into terms: a word or a quoted phrase, optionally led by c- z- n- to pin it to one field. Without a key a term matches any field.
local function splitTerms(content)
    local terms = {}
    local rest = content
    while true do
        rest = rest:match("^%s*(.*)$")
        if rest == "" then break end
        local key = rest:match("^([cznCZN])%-")
        if key then rest = rest:sub(3) end
        local text
        if rest:sub(1, 1) == '"' then
            local close = rest:find('"', 2, true)
            text = rest:sub(2, (close or #rest + 1) - 1)
            rest = close and rest:sub(close + 1) or ""
        else
            text = rest:match("^%S*")
            rest = rest:sub(#text + 1)
        end
        text = trim(text):lower()
        if text ~= "" then
            terms[#terms + 1] = { field = key and TERM_FIELDS[key:lower()], text = text }
        end
    end
    return terms
end

local function parseFlags(input)
    local tokens = {}
    for t in input:gmatch("%S+") do tokens[#tokens + 1] = t end
    local cursor = 1
    local opts = { terms = {}, includeTerms = {} }
    while cursor <= #tokens do
        local flag = tokens[cursor]
        local name = flagName(flag)
        local value = tokens[cursor + 1]
        if flag == "-limit" then
            local count = value and tonumber(value)
            if count and count > 0 then
                opts.limit = math.floor(count)
                cursor = cursor + 2
            else
                -- No positive number after it: flag the mistake so the caller can nudge instead of silently whispering everyone.
                opts.limitError = true
                cursor = cursor + 1
            end
        elseif flag == "-cd" then
            opts.useCooldown = true
            local seconds = value and parseDuration(value)
            if seconds then
                opts.cooldownSeconds = seconds
                cursor = cursor + 2
            elseif value and value:match("^%d") then
                -- A digit-led token that isn't a duration is a typo ("3o", "0", "30x"), not message text.
                opts.cdError = value
                cursor = cursor + 2
            else
                cursor = cursor + 1
            end
        elseif BRACKET_FLAGS[name] then
            local content, mistake, nextCursor = readBracket(tokens, cursor, name)
            if not content then
                if not opts.bracketError then opts.bracketError = { flag = name, mistake = mistake } end
            elseif name == "-who" then
                opts.who = content
            else
                -- -skip and -only may repeat; every group adds to the same bucket.
                local bucket = opts[BRACKET_FLAGS[name]]
                for _, term in ipairs(splitTerms(content)) do bucket[#bucket + 1] = term end
            end
            cursor = nextCursor
        else
            break
        end
    end
    local words = {}
    for i = cursor, #tokens do words[#words + 1] = tokens[i] end
    opts.text = table.concat(words, " ")

    -- A known flag inside the message is a misplaced flag, not text to whisper; flags only parse before the message.
    for _, word in ipairs(words) do
        local lowered = word:lower()
        if FLAG_WORDS[lowered] or FLAG_WORDS[flagName(lowered)] then
            opts.flagError = word
            break
        end
    end

    -- A message of only semicolons splits to nothing; treat it as empty so the usage checks catch it.
    if #ns.SplitWhisper(opts.text) == 0 then opts.text = "" end
    return opts
end

-- One worked example per bracket flag and one line per way a group can go wrong, so the nudge names the actual slip.
local BRACKET_EXAMPLES = {
    ["-who"] = "-who (mage 50-60 stormwind)",
    ["-skip"] = "-skip (warlock z-maraudon)",
    ["-only"] = "-only (priest c-paladin)",
}
local BRACKET_MISTAKES = {
    open = "",
    empty = "They're empty.",
    close = "The closing one is missing.",
}

-- Report the first flag mistake so the caller aborts instead of whispering a typo. allowCooldown is false for commands that reject -cd outright, so they can say so instead of correcting its duration.
local function flagMistake(opts, allowCooldown)
    local bracket = opts.bracketError
    if bracket then
        -- Diagnosed first: a group that fell through leaves its words stranded in the message, and blaming those would hide the real mistake.
        local why = BRACKET_MISTAKES[bracket.mistake]
        fail(bracket.flag .. " needs brackets.", (why ~= "" and (why .. " ") or "") .. "e.g. " .. BRACKET_EXAMPLES[bracket.flag] .. ".")
    elseif opts.limitError then
        fail("-limit needs a number.", "e.g. -limit 10.")
    elseif allowCooldown and opts.cdError then
        fail("-cd needs a duration.", "\"" .. opts.cdError .. "\" isn't one. " .. DURATION_HINT)
    elseif opts.flagError then
        fail("Flags go before the message.", "\"" .. opts.flagError .. "\" landed inside it.")
    else
        return false
    end
    return true
end

-- A -who that failed to parse still counts as used, so commands without a /who can reject it by name.
local function usedWho(opts)
    return opts.who ~= nil or (opts.bracketError ~= nil and opts.bracketError.flag == "-who")
end

-- Shared with /rr so both commands parse flags and report mistakes the same way; /rr only acts on -limit and rejects -cd.
ns.ParseFlags = parseFlags
ns.FlagMistake = flagMistake
ns.UsedWho = usedWho
ns.LoadBlocked = loadBlocked
ns.IsBlocked = isBlocked

-- A keyed term matches one field; a bare term is a substring of the class, the zone or the name, so "war" catches Warriors, Warsong Gulch and Warence alike.
local function matchesTerm(whoInfo, term)
    local fields = { class = whoInfo.classStr, zone = whoInfo.area, name = whoInfo.fullName }
    if term.field then
        return (fields[term.field] or ""):lower():find(term.text, 1, true) ~= nil
    end
    for _, value in pairs(fields) do
        if value and value:lower():find(term.text, 1, true) then return true end
    end
    return false
end

local function isFiltered(whoInfo, terms)
    for _, term in ipairs(terms) do
        if matchesTerm(whoInfo, term) then return true end
    end
    return false
end

-- -only is the inverse of -skip: with terms set, a player must match at least one term to qualify. No terms = everyone.
local function isIncluded(whoInfo, includeTerms)
    if #includeTerms == 0 then return true end
    for _, term in ipairs(includeTerms) do
        if matchesTerm(whoInfo, term) then return true end
    end
    return false
end

-- Load the lists a blast reads and writes, once per command.
local function loadLists(opts)
    local lists = { blocked = loadBlocked() }
    if opts.useCooldown then
        lists.cooldown = loadCooldowns()
        lists.cooldownSeconds = opts.cooldownSeconds
    end
    return lists
end

-- Cap to -limit, report one status line, queue the sends and stamp the persistent lists. Shared by /ww and /ws so the two can't drift apart; only /ww passes track, because sellers never enter the /rr exchange.
local function sendBlast(opts, lists, eligible, counts, total, singular, multiple, track)
    local sendCount = opts.limit and math.min(opts.limit, #eligible) or #eligible
    counts.limit = #eligible - sendCount
    local pool = total .. " " .. plural(total, singular, multiple)

    if sendCount == 0 then
        fail("Nobody to whisper.", "None of " .. pool .. " qualify.")
        ns.SkipLine(counts, total)
        return
    end

    -- One fact per line, in the order they matter: who hears it, who doesn't and why, what the lists recorded, then the message itself. The queue's counter picks up from there.
    local eta = ns.SendEta(sendCount * #ns.SplitWhisper(opts.text))
    local tail = eta and (", " .. eta) or ""
    -- The cooldown rides on the opening line rather than taking one of its own: it is a property of this run, not an event in it.
    if lists.cooldownSeconds then tail = tail .. ", " .. ns.Tint("cool", ns.FormatDuration(lists.cooldownSeconds) .. " cooldown") end
    ok("Whispering", (sendCount == total and "all " or sendCount .. " of ") .. pool .. tail .. ".")
    ns.SkipLine(counts, total - sendCount)
    ns.QuoteMessage(opts.text)

    local sentNames = track and {}
    for i = 1, sendCount do
        local name = eligible[i]
        ns.QueueWhisper(opts.text, name)
        if sentNames then sentNames[#sentNames + 1] = name end
        -- Only a timed -cd records new recipients; bare -cd just reads the list.
        if lists.cooldown and lists.cooldownSeconds then lists.cooldown[name:lower()] = time() + lists.cooldownSeconds end
    end

    -- /rr replies to these names once they whisper back.
    if sentNames then ns.TrackWhispered(sentNames) end
end

local function dispatchWho(opts)
    local count = C_FriendList.GetNumWhoResults()
    if count == 0 then
        fail("No /who results.", "Run /who first, or use -who (…).")
        return
    end

    local groupSet = buildGroupSet()
    local lists = loadLists(opts)

    -- Keys are the ones ns.SkipReasons reads, counted in the order the checks run.
    local counts = { blocked = 0, cooldown = 0, filter = 0, group = 0, recentGroup = 0 }
    local eligible = {}
    for i = 1, count do
        local whoInfo = C_FriendList.GetWhoInfo(i)
        local fullName = whoInfo and whoInfo.fullName
        if fullName then
            local short = nameOnly(fullName)
            if groupSet[short] then
                counts.group = counts.group + 1
            elseif wasRecentlyGrouped(short) then
                counts.recentGroup = counts.recentGroup + 1
            elseif isBlocked(lists.blocked, fullName) then
                counts.blocked = counts.blocked + 1
            elseif isFiltered(whoInfo, opts.terms) or not isIncluded(whoInfo, opts.includeTerms) then
                counts.filter = counts.filter + 1
            elseif lists.cooldown and onCooldown(lists.cooldown, fullName) then
                counts.cooldown = counts.cooldown + 1
            else
                eligible[#eligible + 1] = fullName
            end
        end
    end

    sendBlast(opts, lists, eligible, counts, count, "/who result", "/who results", true)
end

local WHO_TIMEOUT = 6      -- Seconds to wait for the server's answer before aborting, since the who list still holds the previous search.
local PANEL_RESTORE = 8    -- The server answers some queries seconds late; re-arming the panel too early lets a straggler pop it open.

-- Put the who plumbing back where the panel expects it: results to chat unless the panel is open, and the panel listening again.
local function restoreWhoUi()
    C_FriendList.SetWhoToUi(WhoFrame ~= nil and WhoFrame:IsShown() or false)
    if FriendsFrame then FriendsFrame:RegisterEvent("WHO_LIST_UPDATE") end
end

-- -who runs the search itself: results go to the API list instead of chat, the Friends panel is deafened so it can't pop open, and the blast waits for this query's own results. A timeout aborts rather than dispatching, because the who list still holds the previous search and whispering those people would be the wrong run.
local function runWho(opts)
    if FriendsFrame then FriendsFrame:UnregisterEvent("WHO_LIST_UPDATE") end
    C_FriendList.SetWhoToUi(true)

    local waiter = CreateFrame("Frame")
    local settled = false
    local function stop()
        settled = true
        waiter:UnregisterEvent("WHO_LIST_UPDATE")
        waiter:SetScript("OnEvent", nil)
    end

    waiter:RegisterEvent("WHO_LIST_UPDATE")
    -- A /who fires WHO_LIST_UPDATE twice: once to clear the old rows, then again when the server's answer lands. Only the second one carries results.
    waiter:SetScript("OnEvent", function()
        if settled then return end
        local count, total = C_FriendList.GetNumWhoResults()
        if count == 0 then return end
        stop()
        if total and total > count then
            note(count .. " of " .. total .. " matches shown. Narrow the filter for the rest.")
        end
        dispatchWho(opts)
    end)

    C_Timer.After(WHO_TIMEOUT, function()
        if settled then return end
        stop()
        fail("Nobody found.", "\"" .. opts.who .. "\" came back empty or /who is throttled. Retry in a few seconds.")
    end)
    -- Restore on a fixed clock rather than on completion, because a straggling answer after the timeout would otherwise pop the panel.
    C_Timer.After(PANEL_RESTORE, restoreWhoUi)

    C_FriendList.SendWho(opts.who)
end

local function whisperWho(input)
    local opts = parseFlags(trim(input))
    if flagMistake(opts, true) then return end
    if not opts.text or opts.text == "" then
        note("Usage: /ww MESSAGE whispers your /who results, e.g. /ww LFM SM live. /ss lists every flag.")
        return
    end
    if opts.who then
        runWho(opts)
    else
        dispatchWho(opts)
    end
end

local function collectAuctionSellers()
    local count = GetNumAuctionItems("list")
    if not count or count == 0 then return nil end
    local seen = {}
    local order = {}
    local me = UnitName("player")
    for i = 1, count do
        local _, _, _, _, _, _, _, _, _, _, _, _, _, owner, ownerFullName = GetAuctionItemInfo("list", i)
        local name = ownerFullName or owner
        if name and name ~= "" and name ~= me and not seen[name] then
            seen[name] = true
            order[#order + 1] = name
        end
    end
    return order
end

local function whisperSellers(input)
    local opts = parseFlags(trim(input))
    if flagMistake(opts, true) then return end
    if usedWho(opts) then
        fail("-who doesn't apply to /ws.", "It reads the Browse tab.")
        return
    end
    -- Sellers carry no class or zone, so the term filters can't apply here.
    if #opts.terms > 0 or #opts.includeTerms > 0 then
        fail("-skip and -only don't apply to /ws.", "Sellers carry no class or zone.")
        return
    end
    if not opts.text or opts.text == "" then
        note("Usage: /ws MESSAGE whispers every seller in the Browse tab, e.g. /ws still selling your Black Lotus?")
        return
    end
    if not AuctionFrame or not AuctionFrame:IsShown() then
        fail("Auction house closed.", "Open the Browse tab first.")
        return
    end
    local names = collectAuctionSellers()
    if not names or #names == 0 then
        fail("No sellers", "in the Browse results.")
        return
    end

    local lists = loadLists(opts)
    local counts = { blocked = 0, cooldown = 0 }
    local eligible = {}
    for _, sellerName in ipairs(names) do
        if isBlocked(lists.blocked, sellerName) then
            counts.blocked = counts.blocked + 1
        elseif lists.cooldown and onCooldown(lists.cooldown, sellerName) then
            counts.cooldown = counts.cooldown + 1
        else
            eligible[#eligible + 1] = sellerName
        end
    end

    sendBlast(opts, lists, eligible, counts, #names, "seller", "sellers")
end

-- Display form with a leading capital, matching how names render in game.
local function displayName(name)
    return name:sub(1, 1):upper() .. name:sub(2)
end

local function listBlocked()
    local names = {}
    for _, shown in pairs(loadBlocked()) do
        names[#names + 1] = shown
    end
    if #names == 0 then
        note("Block list is empty.")
        return
    end
    table.sort(names)
    note(#names .. " blocked: " .. table.concat(names, ", ") .. ".")
end

local function blockName(name)
    if name:find("%s") then
        fail("One name at a time.", "e.g. /ss -block Thrall.")
        return
    end
    local blocked = loadBlocked()
    local key = name:lower()
    if blocked[key] then
        note(blocked[key] .. " is already blocked.")
        return
    end
    blocked[key] = displayName(name)
    ok("Blocked", blocked[key] .. ". /ss -unblock " .. blocked[key] .. " undoes it.")
end

local function unblockName(name)
    local blocked = loadBlocked()
    local key = name:lower()
    local shown = blocked[key]
    if not shown then
        note(displayName(name) .. " isn't on the block list.")
        return
    end
    blocked[key] = nil
    ok("Unblocked", shown .. ".")
end

local MANUAL_COOLDOWN = 30 * 86400 -- /ss -cd NAME without a duration: the long memory the old ignore list gave.

-- Put one player on cooldown by hand, the same list -cd sends build.
local function cooldownName(arg)
    local name, duration, extra = arg:match("^(%S+)%s*(%S*)%s*(.*)$")
    if extra ~= "" then
        fail("One name, then an optional duration.", "e.g. /ss -cd Thrall 30d.")
        return
    end
    local seconds = MANUAL_COOLDOWN
    if duration ~= "" then
        seconds = parseDuration(duration)
        if not seconds then
            fail("-cd needs a duration.", "\"" .. duration .. "\" isn't one. " .. DURATION_HINT)
            return
        end
    end
    loadCooldowns()[name:lower()] = time() + seconds
    ok("On cooldown", displayName(name) .. ", " .. ns.FormatDuration(seconds) .. ".")
end

-- The cooldown list runs into the thousands, so its size and its longest remaining wait are the two facts worth knowing before deciding whether to clear it.
local function cooldownStatus()
    local cooldowns = loadCooldowns()
    local now = time()
    local count, longest = 0, 0
    for _, expiry in pairs(cooldowns) do
        count = count + 1
        if expiry - now > longest then longest = expiry - now end
    end
    if count == 0 then
        note("Nobody is on cooldown.")
        return
    end
    note(count .. " on cooldown, longest " .. ns.FormatRemaining(longest) .. " left. /ss -cd clear empties it.")
end

local function quietCommand(arg)
    local target
    if arg == "" then
        target = not ns.QuietBlasts()
    elseif arg == "on" then
        target = true
    elseif arg == "off" then
        target = false
    else
        note("Usage: /ss quiet toggles the counter, /ss quiet on and /ss quiet off set it.")
        return
    end
    ns.SetQuietBlasts(target)
    if target then
        ok("Quiet mode on.", "Runs show one counter instead of every whisper.")
    else
        ok("Quiet mode off.", "Every whisper prints again.")
    end
end

local function adminCommand(input)
    -- Keep the raw form so block/unblock names keep their capitalization.
    local raw = trim(input)
    input = raw:lower()
    if input == "" or input == "help" then
        ns.ToggleHelp()
    elseif input == "-block" or input == "-block list" then
        listBlocked()
    elseif input:match("^%-block%s") then
        blockName(trim(raw:match("^%S+%s+(.*)$")))
    elseif input == "-unblock" then
        note("Usage: /ss -unblock NAME.")
    elseif input:match("^%-unblock%s") then
        unblockName(trim(raw:match("^%S+%s+(.*)$")))
    elseif input == "-cd" then
        cooldownStatus()
    elseif input == "-cd clear" then
        clearCooldowns()
        ok("Cooldown list cleared.")
    elseif input:match("^%-cd%s") then
        cooldownName(trim(raw:match("^%S+%s+(.*)$")))
    elseif input:match("^%-ignore") then
        -- The old command still gets a pointer, so muscle memory lands somewhere useful.
        note("-ignore is now -cd 30d. /ss -cd manages the list.")
    elseif input == "quiet" then
        quietCommand("")
    elseif input:match("^quiet%s") then
        quietCommand(trim(input:match("^%S+%s+(.*)$")))
    elseif input == "rate" then
        note("Send rate " .. string.format("%.2f", ns.PacingRate()) .. "/s, learned from the server. /ss rate reset restores the default.")
    elseif input == "rate reset" then
        ok("Rate reset.", string.format("%.2f", ns.ResetPacingRate()) .. "/s until the server teaches otherwise.")
    elseif input == "stop" then
        local sent, dropped = ns.CancelQueue()
        if sent == 0 and dropped == 0 then
            fail("Nothing to stop.", "No whispers are queued.")
        else
            ok("Stopped.", sent .. " sent, " .. dropped .. " " .. plural(dropped, "whisper", "whispers") .. " cancelled.")
        end
    else
        fail("Unknown command", "\"" .. raw .. "\". /ss opens the reference.")
    end
end

local function blendWhisperColors(_, event, arg1)
    if event == "UPDATE_CHAT_COLOR" and arg1 ~= "WHISPER" and arg1 ~= "WHISPER_INFORM" then
        return
    end
    if applyingColor then return end
    local outgoing = ChatTypeInfo["WHISPER_INFORM"]
    local incoming = ChatTypeInfo["WHISPER"]
    if not outgoing or not incoming then return end
    applyingColor = true
    incoming.r = outgoing.r + (1 - outgoing.r) * 0.5
    incoming.g = outgoing.g + (1 - outgoing.g) * 0.5
    incoming.b = outgoing.b + (1 - outgoing.b) * 0.5
    applyingColor = false
end

local colorWatch = CreateFrame("Frame")
colorWatch:RegisterEvent("PLAYER_ENTERING_WORLD")
colorWatch:RegisterEvent("UPDATE_CHAT_COLOR")
colorWatch:SetScript("OnEvent", blendWhisperColors)

-- Saved variables are never rewritten wholesale, so a removed feature's data sits in the file forever unless it is dropped by name. These two are all that is left of a chat scanner and a login banner.
local DEAD_KEYS = { "chatScan", "showLoginBanner", "ignoredByChar", "ignored", "cooldownByChar" }

local COOLDOWN_FORMAT = 2          -- Bumped when the cooldown list changes shape, so the conversion below runs once.
local IGNORE_DAYS = 30             -- The old ignore list aged entries out after this long.
local LEGACY_COOLDOWN_GRACE = 3600 -- Old cooldown stamps carried no duration; an hour keeps a run in progress honest without holding names for long.

-- Cooldowns used to store the send time and apply the duration when read, and the ignore list was a separate 30-day memory. Both fold into one list of expiry times: ignore entries keep the rest of their 30 days, old cooldown stamps get an hour.
local function migrateCooldowns(db)
    if (db.cooldownFormat or 1) >= COOLDOWN_FORMAT then return end
    local merged = {}
    local function keep(name, expiry)
        local key = name:lower()
        merged[key] = math.max(merged[key] or 0, expiry)
    end
    for name, stamp in pairs(db.cooldownAccount or {}) do
        if type(stamp) == "number" then keep(name, stamp + LEGACY_COOLDOWN_GRACE) end
    end
    for name, stamp in pairs(db.ignoredAccount or {}) do
        if type(stamp) == "number" then keep(name, stamp + IGNORE_DAYS * 86400) end
    end
    db.cooldownAccount = merged
    db.ignoredAccount = nil
    db.cooldownFormat = COOLDOWN_FORMAT
end

ns.MigrateCooldowns = migrateCooldowns

local dbCleanup = CreateFrame("Frame")
dbCleanup:RegisterEvent("ADDON_LOADED")
dbCleanup:SetScript("OnEvent", function(self, _, addon)
    if addon ~= ADDON then return end
    self:UnregisterAllEvents()
    SuperSocialDB = SuperSocialDB or {}
    for _, key in ipairs(DEAD_KEYS) do SuperSocialDB[key] = nil end
    migrateCooldowns(SuperSocialDB)
end)

SLASH_WHISPERTARGET1 = "/wt"
SlashCmdList["WHISPERTARGET"] = whisperTarget

SLASH_WHISPERWHO1 = "/ww"
SlashCmdList["WHISPERWHO"] = whisperWho

SLASH_WHISPERSELLERS1 = "/ws"
SlashCmdList["WHISPERSELLERS"] = whisperSellers

SLASH_SUPERSOCIAL1 = "/ss"
SlashCmdList["SUPERSOCIAL"] = adminCommand
