local ADDON, ns = ...

local applyingColor = false

local ok = ns.Ok
local fail = ns.Fail
local note = ns.Note
local plural = ns.Plural

local function trim(s)
    return (s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local IGNORE_DAYS = 30 -- Ignore entries older than this age out, so the list can't grow without bound.

local function loadSkip()
    SuperSocialDB = SuperSocialDB or {}

    -- One account-wide ignore list shared by every character: lowercased name -> time added.
    local bucket = SuperSocialDB.ignoredAccount or {}
    SuperSocialDB.ignoredAccount = bucket

    -- Age out stale entries so the list can't grow without bound; a non-number stamp is pre-migration debris and goes too.
    local cutoff = time() - IGNORE_DAYS * 86400
    for name, stamp in pairs(bucket) do
        if type(stamp) ~= "number" or stamp < cutoff then bucket[name] = nil end
    end

    return bucket
end

local function clearSkip()
    wipe(loadSkip())
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

    -- One account-wide cooldown list shared by every character, so a relog onto an alt keeps everyone's cooldown running.
    local bucket = SuperSocialDB.cooldownAccount or {}
    SuperSocialDB.cooldownAccount = bucket
    return bucket
end

local function pruneCooldowns(bucket, cooldownSeconds)
    local cutoff = time() - cooldownSeconds
    for n, ts in pairs(bucket) do
        if ts < cutoff then bucket[n] = nil end
    end
end

local function isCool(bucket, name, cooldownSeconds)
    local ts = bucket[name]
    if not ts then return true end
    -- Bare -cd has no duration: any entry on the list counts as still cooling.
    if not cooldownSeconds then return false end
    return (time() - ts) >= cooldownSeconds
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

-- The ignore list needs the same two-form lookup, so a hand-added short name still catches the player's "Name-Realm" form in a /who.
local function isIgnored(skip, fullName)
    if skip[fullName:lower()] then return true end
    local short = nameOnly(fullName)
    return short ~= fullName and skip[short:lower()] ~= nil or false
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
    local useSkip = false
    if tokens[cursor] == "-ignore" then
        useSkip = true
        cursor = cursor + 1
    end
    local parts = ns.SplitWhisper(table.concat(tokens, " ", cursor))
    if #parts == 0 then
        note("Usage: /wt MESSAGE — whisper your current target (-ignore also adds them to the ignore list). e.g. /wt got room for one more?")
        return
    end
    if not (UnitExists("target") and UnitIsPlayer("target")) then
        fail("No target selected.", "Pick a player first.")
        return
    end
    local targetName = UnitName("target")
    if isBlocked(loadBlocked(), targetName) then
        fail("Blocked.", targetName .. " is on the block list. /ss -unblock " .. targetName .. " removes them.")
        return
    end
    -- Through the queue for cap rescue, flagged personal so /rr treats it as an answer, not a blast.
    for _, part in ipairs(parts) do
        ns.QueueWhisper(part, targetName, "personal")
    end
    ok("Whispered", targetName .. ".")
    if useSkip then loadSkip()[targetName:lower()] = time() end
end

-- Every flag parseFlags understands, used to catch one misplaced after the message.
local FLAG_WORDS = { ["-limit"] = true, ["-skip"] = true, ["-only"] = true, ["-ignore"] = true, ["-cd"] = true, ["-wait"] = true, ["-who"] = true }

-- A token is part of a /who filter when it looks like one: a level, a range, a keyed term (c- z- r- n- g-), or a quoted continuation. The first token shaped like neither starts the message, so -who needs no closing delimiter.
local function isWhoTerm(token, openQuote)
    if openQuote then return true end
    return token:match("^%d+$") ~= nil
        or token:match("^%d+%-%d+$") ~= nil
        or token:match("^[cnzrgCNZRG]%-") ~= nil
        or token:match('^"') ~= nil
end

local function parseFlags(input)
    local tokens = {}
    for t in input:gmatch("%S+") do tokens[#tokens + 1] = t end
    local cursor = 1
    local opts = { terms = {}, includeTerms = {}, useSkip = false }
    while cursor <= #tokens do
        local flag = tokens[cursor]
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
            local minutes = value and tonumber(value)
            if minutes and minutes > 0 then
                opts.cooldownSeconds = math.floor(minutes * 60)
                cursor = cursor + 2
            elseif value and value:match("^%d") then
                -- A digit-led token that isn't a positive number is a typo ("3o", "0"), not message text.
                opts.cdError = value
                cursor = cursor + 2
            else
                cursor = cursor + 1
            end
        elseif flag == "-ignore" then
            opts.useSkip = true
            cursor = cursor + 1
        elseif flag == "-wait" then
            opts.wait = true
            cursor = cursor + 1
        elseif flag == "-who" then
            local terms = {}
            local openQuote = false
            cursor = cursor + 1
            while cursor <= #tokens and isWhoTerm(tokens[cursor], openQuote) do
                terms[#terms + 1] = tokens[cursor]
                -- An odd number of quotes flips the state, so z-"Blackrock Depths" absorbs both tokens.
                local _, quotes = tokens[cursor]:gsub('"', "")
                if quotes % 2 == 1 then openQuote = not openQuote end
                cursor = cursor + 1
            end
            if #terms == 0 then
                opts.whoError = true
            else
                opts.who = table.concat(terms, " ")
            end
        elseif (flag == "-skip" or flag == "-only") and value then
            local bucket = (flag == "-only") and opts.includeTerms or opts.terms
            local raw = value
            cursor = cursor + 2
            -- Keep absorbing tokens while the comma list is still open, so "-skip Maraudon, Warlock" works with spaces around the commas.
            while cursor <= #tokens do
                local listContinues = raw:match(",%s*$") or tokens[cursor]:match("^,")
                if not listContinues then break end
                raw = raw .. " " .. tokens[cursor]
                cursor = cursor + 1
            end
            for term in raw:gmatch("[^,]+") do
                local cleaned = trim(term):lower()
                if cleaned ~= "" then
                    bucket[#bucket + 1] = cleaned
                end
            end
        else
            break
        end
    end
    local words = {}
    for i = cursor, #tokens do words[#words + 1] = tokens[i] end
    opts.text = table.concat(words, " ")

    -- A known flag inside the message is a misplaced flag, not text to whisper; flags only parse before the message.
    for _, word in ipairs(words) do
        if FLAG_WORDS[word:lower()] then
            opts.flagError = word
            break
        end
    end

    -- A message of only semicolons splits to nothing; treat it as empty so the usage checks catch it.
    if #ns.SplitWhisper(opts.text) == 0 then opts.text = "" end
    return opts
end

-- Report the first flag mistake so the caller aborts instead of whispering a typo. Examples are per command; no cdEg means the caller rejects -cd itself.
local function flagMistake(opts, limitEg, cdEg)
    if opts.limitError then
        fail("-limit needs a number.", "e.g. " .. limitEg .. ".")
    elseif cdEg and opts.cdError then
        fail("-cd needs minutes as a number.", "\"" .. opts.cdError .. "\" isn't one. e.g. " .. cdEg .. ".")
    elseif opts.flagError then
        fail("Flags go before the message.", opts.flagError .. " would have been whispered as text. e.g. " .. limitEg .. ".")
    else
        return false
    end
    return true
end

-- Shared with /rr so both commands parse flags and report mistakes the same way; /rr only acts on -limit and rejects -cd.
ns.ParseFlags = parseFlags
ns.FlagMistake = flagMistake
ns.LoadBlocked = loadBlocked
ns.IsBlocked = isBlocked

-- A term matches a player when it's a substring of their class, their zone or their name, so "war" catches Warriors, Warsong Gulch and Warence alike.
local function matchesTerm(whoInfo, term)
    local class = (whoInfo.classStr or ""):lower()
    local area = (whoInfo.area or ""):lower()
    local name = (whoInfo.fullName or ""):lower()
    if class ~= "" and class:find(term, 1, true) then return true end
    if area ~= "" and area:find(term, 1, true) then return true end
    if name ~= "" and name:find(term, 1, true) then return true end
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
    local lists = {
        blocked = loadBlocked(),
        skip = opts.useSkip and loadSkip() or nil,
    }
    if opts.useCooldown then
        lists.cooldown = loadCooldowns()
        if opts.cooldownSeconds then
            pruneCooldowns(lists.cooldown, opts.cooldownSeconds)
            lists.cooldownMinutes = math.floor(opts.cooldownSeconds / 60)
        end
    end
    return lists
end

-- Cap to -limit, report one status line, queue the sends and stamp the persistent lists. Shared by /ww and /ws so the two can't drift apart; only /ww passes track, because sellers never enter the /rr exchange.
local function sendBlast(opts, lists, eligible, counts, total, singular, multiple, track)
    local sendCount = opts.limit and math.min(opts.limit, #eligible) or #eligible
    counts.limit = #eligible - sendCount
    local pool = total .. " " .. plural(total, singular, multiple)

    if sendCount == 0 then
        fail("Nobody to whisper.", "None of " .. pool .. " are eligible.")
        ns.SkipLine(counts, total)
        return
    end

    -- One fact per line, in the order they matter: who hears it, who doesn't and why, what the lists recorded, then the message itself. The queue's counter picks up from there.
    local eta = ns.SendEta(sendCount * #ns.SplitWhisper(opts.text))
    ok("Whispering", (sendCount == total and "all " or sendCount .. " of ") .. pool .. (eta and (", " .. eta) or "") .. ".")
    ns.SkipLine(counts, total - sendCount)
    ns.AppliedLine(sendCount, lists.skip ~= nil, lists.cooldownMinutes)
    ns.QuoteMessage(opts.text)

    local sentNames = track and {}
    for i = 1, sendCount do
        local name = eligible[i]
        ns.QueueWhisper(opts.text, name)
        if sentNames then sentNames[#sentNames + 1] = name end
        if lists.skip then lists.skip[name:lower()] = time() end
        -- Only a timed -cd records new recipients; bare -cd just reads the list.
        if lists.cooldown and lists.cooldownMinutes then lists.cooldown[name] = time() end
    end

    -- /rr replies to these names once they whisper back.
    if sentNames then ns.TrackWhispered(sentNames) end
end

local function dispatchWho(opts)
    local count = C_FriendList.GetNumWhoResults()
    if count == 0 then
        fail("No /who results.", "Run /who first.")
        return
    end

    local groupSet = buildGroupSet()
    local lists = loadLists(opts)

    -- Keys are the ones ns.SkipReasons reads, counted in the order the checks run.
    local counts = { blocked = 0, skiplist = 0, cooldown = 0, filter = 0, group = 0, recentGroup = 0 }
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
            elseif lists.skip and isIgnored(lists.skip, fullName) then
                counts.skiplist = counts.skiplist + 1
            elseif lists.cooldown and not isCool(lists.cooldown, fullName, opts.cooldownSeconds) then
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
            note(count .. " of " .. total .. " online match. Narrow the filter to reach the rest.")
        end
        dispatchWho(opts)
    end)

    C_Timer.After(WHO_TIMEOUT, function()
        if settled then return end
        stop()
        fail("Nobody found.", "\"" .. opts.who .. "\" came back empty, or /who was throttled. Try again in a few seconds.")
    end)
    -- Restore on a fixed clock rather than on completion, because a straggling answer after the timeout would otherwise pop the panel.
    C_Timer.After(PANEL_RESTORE, restoreWhoUi)

    C_FriendList.SendWho(opts.who)
end

-- -wait lets a one-click macro send /who then /ww: we hold the whisper until the next WHO_LIST_UPDATE brings the fresh results, with a timeout so a dropped update never leaves the command hanging.
local function waitForWho(opts)
    local waiter = CreateFrame("Frame")
    local done = false
    local function finish()
        if done then return end
        done = true
        waiter:UnregisterEvent("WHO_LIST_UPDATE")
        waiter:SetScript("OnEvent", nil)
        dispatchWho(opts)
    end
    waiter:RegisterEvent("WHO_LIST_UPDATE")
    -- A /who fires WHO_LIST_UPDATE twice: once to clear the old rows (still 0), then again when the server's results land. Wait for the one with results.
    waiter:SetScript("OnEvent", function()
        if C_FriendList.GetNumWhoResults() > 0 then finish() end
    end)
    -- Fallback: if nothing ever arrives, dispatch anyway so the command can't hang.
    C_Timer.After(5, finish)
end

local function whisperWho(input)
    local opts = parseFlags(trim(input))
    -- The -who diagnosis first: a filter that fell through leaves flags stranded in the message, and blaming those would hide the real mistake.
    if opts.whoError then
        fail("-who needs a filter.", "Terms are level ranges and keyed words (c- z- r- n- g-), e.g. /ww -who z-felwood c-warlock 50-60 LFM.")
        return
    end
    if flagMistake(opts, "/ww -limit 10 LFM SM live", "/ww -cd 30 WTB Black Lotus") then return end
    if opts.who and opts.wait then
        fail("-wait doesn't combine with -who.", "-who runs its own /who and waits for the answer already.")
        return
    end
    if not opts.text or opts.text == "" then
        note("Usage: /ww MESSAGE — whisper everyone in your current /who results. e.g. /ww LFM SM live. Type /ss for all options.")
        return
    end
    if opts.who then
        runWho(opts)
    elseif opts.wait then
        waitForWho(opts)
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
    if flagMistake(opts, "/ws -limit 10 still selling?", "/ws -cd 30 still selling?") then return end
    if opts.who or opts.whoError then
        fail("-who doesn't apply to /ws.", "It whispers the sellers in the Browse tab, no /who involved.")
        return
    end
    -- Sellers carry no class or zone, so the term filters can't apply here.
    if #opts.terms > 0 or #opts.includeTerms > 0 then
        fail("-skip and -only don't apply to /ws.", "Sellers carry no class or zone data.")
        return
    end
    if not opts.text or opts.text == "" then
        note("Usage: /ws MESSAGE — whisper every seller in the auction house Browse tab. e.g. /ws still selling your Black Lotus?")
        return
    end
    if not AuctionFrame or not AuctionFrame:IsShown() then
        fail("Auction house closed.", "Open the Browse tab first.")
        return
    end
    local names = collectAuctionSellers()
    if not names or #names == 0 then
        fail("No sellers", "in the current Browse results.")
        return
    end

    local lists = loadLists(opts)
    local counts = { blocked = 0, skiplist = 0, cooldown = 0 }
    local eligible = {}
    for _, sellerName in ipairs(names) do
        if isBlocked(lists.blocked, sellerName) then
            counts.blocked = counts.blocked + 1
        elseif lists.skip and isIgnored(lists.skip, sellerName) then
            counts.skiplist = counts.skiplist + 1
        elseif lists.cooldown and not isCool(lists.cooldown, sellerName, opts.cooldownSeconds) then
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
        note("Block list is empty. /ss -block NAME adds someone.")
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
    ok("Blocked", blocked[key] .. ". No command will whisper them. /ss -unblock " .. blocked[key] .. " undoes it.")
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

local function ignoreName(name)
    if name:find("%s") then
        fail("One name at a time.", "e.g. /ss -ignore Thrall.")
        return
    end
    local skip = loadSkip()
    local shown = displayName(name)
    local key = name:lower()
    if skip[key] then
        note(shown .. " is already on the ignore list.")
        return
    end
    skip[key] = time()
    ok("Ignoring", shown .. ". Sends with -ignore skip them. /ss -ignore clear empties the list.")
end

-- The ignore list runs into the thousands, so its size and age are the two facts worth knowing before deciding whether to clear it.
local function ignoreStatus()
    local skip = loadSkip()
    local count, oldest = 0, nil
    for _, stamp in pairs(skip) do
        count = count + 1
        if not oldest or stamp < oldest then oldest = stamp end
    end
    if count == 0 then
        note("Ignore list is empty. /ss -ignore NAME adds someone, and -ignore on a send fills it as it goes.")
        return
    end
    local days = math.floor((time() - oldest) / 86400)
    local age = (days == 0) and "today" or (days .. " " .. plural(days, "day", "days") .. " ago")
    note(count .. " on the ignore list, oldest added " .. age .. ". Entries age out after " .. IGNORE_DAYS
        .. " days. /ss -ignore NAME adds one, /ss -ignore clear empties the list.")
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
        note("Usage: /ss quiet — hide your own outgoing lines during a /ww or /ws run. /ss quiet on and /ss quiet off set it outright.")
        return
    end
    ns.SetQuietBlasts(target)
    if target then
        ok("Quiet mode on.", "A /ww or /ws run closes with its verdict instead of printing every whisper. /wt and /rr still show.")
    else
        ok("Quiet mode off.", "Every outgoing whisper prints to chat again.")
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
        note("Usage: /ss -unblock NAME — remove a player from the block list.")
    elseif input:match("^%-unblock%s") then
        unblockName(trim(raw:match("^%S+%s+(.*)$")))
    elseif input == "-ignore" then
        ignoreStatus()
    elseif input == "-ignore clear" then
        clearSkip()
        ok("Ignore list cleared.")
    elseif input:match("^%-ignore%s") then
        ignoreName(trim(raw:match("^%S+%s+(.*)$")))
    elseif input == "-cd clear" then
        clearCooldowns()
        ok("Cooldown history cleared.")
    elseif input:match("^%-cd") then
        note("Usage: /ss -cd clear — empty the cooldown history.")
    elseif input == "quiet" then
        quietCommand("")
    elseif input:match("^quiet%s") then
        quietCommand(trim(input:match("^%S+%s+(.*)$")))
    elseif input == "rate" then
        note("Sending at " .. string.format("%.2f", ns.PacingRate()) .. " whispers per second, learned from the server. /ss rate reset restores the default.")
    elseif input == "rate reset" then
        ok("Rate reset.", "Sending at " .. string.format("%.2f", ns.ResetPacingRate()) .. "/s until the server teaches otherwise.")
    elseif input == "stop" then
        local sent, dropped = ns.CancelQueue()
        if sent == 0 and dropped == 0 then
            fail("Nothing to stop.", "No whispers are queued.")
        else
            ok("Stopped.", sent .. " sent, " .. dropped .. " " .. plural(dropped, "whisper", "whispers") .. " cancelled.")
        end
    else
        fail("Unknown command.", "\"" .. raw .. "\" isn't one. /ss opens the reference window.")
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

local dbCleanup = CreateFrame("Frame")
dbCleanup:RegisterEvent("ADDON_LOADED")
dbCleanup:SetScript("OnEvent", function(self, _, addon)
    if addon ~= ADDON then return end
    self:UnregisterAllEvents()
    SuperSocialDB = SuperSocialDB or {}
    for _, key in ipairs(DEAD_KEYS) do SuperSocialDB[key] = nil end
end)

SLASH_WHISPERTARGET1 = "/wt"
SlashCmdList["WHISPERTARGET"] = whisperTarget

SLASH_WHISPERWHO1 = "/ww"
SlashCmdList["WHISPERWHO"] = whisperWho

SLASH_WHISPERSELLERS1 = "/ws"
SlashCmdList["WHISPERSELLERS"] = whisperSellers

SLASH_SUPERSOCIAL1 = "/ss"
SlashCmdList["SUPERSOCIAL"] = adminCommand
