local _, ns = ...

local applyingColor = false

local tint = ns.Tint
local status = ns.Status
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

    -- Migrate per-character buckets into the shared list.
    if SuperSocialDB.ignoredByChar then
        for _, charBucket in pairs(SuperSocialDB.ignoredByChar) do
            for name in pairs(charBucket) do
                bucket[name] = true
            end
        end
        SuperSocialDB.ignoredByChar = nil
    end

    -- Migrate the pre-per-char flat list as well.
    if SuperSocialDB.ignored then
        for name in pairs(SuperSocialDB.ignored) do
            bucket[name] = true
        end
        SuperSocialDB.ignored = nil
    end

    -- Migrate display-cased keys and bare `true` flags to lowercased keys with timestamps, collected first because pairs forbids adding keys mid-scan.
    local now = time()
    local fixes
    for name, stamp in pairs(bucket) do
        if stamp == true or name:lower() ~= name then
            fixes = fixes or {}
            fixes[name] = (stamp == true) and now or stamp
        end
    end
    if fixes then
        for name, stamp in pairs(fixes) do
            local key = name:lower()
            bucket[name] = nil
            if not bucket[key] or stamp > bucket[key] then bucket[key] = stamp end
        end
    end

    -- Age out stale entries.
    local cutoff = now - IGNORE_DAYS * 86400
    for name, stamp in pairs(bucket) do
        if stamp < cutoff then bucket[name] = nil end
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

    -- One account-wide cooldown list shared by every character, like the ignore list — a relog onto an alt keeps everyone's cooldown running.
    local bucket = SuperSocialDB.cooldownAccount or {}
    SuperSocialDB.cooldownAccount = bucket

    -- Migrate per-character buckets, keeping the newest timestamp per name.
    if SuperSocialDB.cooldownByChar then
        for _, charBucket in pairs(SuperSocialDB.cooldownByChar) do
            for name, ts in pairs(charBucket) do
                if not bucket[name] or ts > bucket[name] then
                    bucket[name] = ts
                end
            end
        end
        SuperSocialDB.cooldownByChar = nil
    end

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
local recentGroupLeftAt = {}  -- short name -> time they left the group
local lastRoster = {}

local rosterWatcher = CreateFrame("Frame")
rosterWatcher:RegisterEvent("GROUP_ROSTER_UPDATE")
rosterWatcher:RegisterEvent("PLAYER_ENTERING_WORLD")
rosterWatcher:SetScript("OnEvent", function()
    local roster = buildGroupSet()
    for name in pairs(lastRoster) do
        if not roster[name] then
            recentGroupLeftAt[name] = time()
        end
    end
    lastRoster = roster
end)

local function wasRecentlyGrouped(short)
    local leftAt = recentGroupLeftAt[short]
    if not leftAt then return false end
    if (time() - leftAt) >= RECENT_GROUP_SECONDS then
        recentGroupLeftAt[short] = nil
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
local FLAG_WORDS = { ["-limit"] = true, ["-skip"] = true, ["-only"] = true, ["-ignore"] = true, ["-cd"] = true, ["-wait"] = true }

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

-- Shared with /rr so both commands parse flags the same way; /rr only acts on -limit and rejects -cd.
ns.ParseFlags = parseFlags
ns.LoadBlocked = loadBlocked
ns.IsBlocked = isBlocked

-- A term matches a player when it's a substring of their class or their zone, so "war" catches both Warriors and Warsong Gulch.
local function matchesTerm(whoInfo, term)
    local class = (whoInfo.classStr or ""):lower()
    local area = (whoInfo.area or ""):lower()
    if class ~= "" and class:find(term, 1, true) then return true end
    if area ~= "" and area:find(term, 1, true) then return true end
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

local function dispatchWho(opts)
    local count = C_FriendList.GetNumWhoResults()
    if count == 0 then
        fail("No /who results.", "Run /who first.")
        return
    end

    local groupSet = buildGroupSet()
    local blocked = loadBlocked()
    local skip = opts.useSkip and loadSkip() or nil
    local cooldownBucket
    local cooldownMinutes
    if opts.useCooldown then
        cooldownBucket = loadCooldowns()
        if opts.cooldownSeconds then
            pruneCooldowns(cooldownBucket, opts.cooldownSeconds)
            cooldownMinutes = math.floor(opts.cooldownSeconds / 60)
        end
    end

    local skippedGroup, skippedRecentGroup, skippedBlocked, skippedFilter, skippedSkip, skippedCool = 0, 0, 0, 0, 0, 0
    local eligible = {}
    for i = 1, count do
        local whoInfo = C_FriendList.GetWhoInfo(i)
        local fullName = whoInfo and whoInfo.fullName
        if fullName then
            local short = nameOnly(fullName)
            if groupSet[short or fullName] then
                skippedGroup = skippedGroup + 1
            elseif wasRecentlyGrouped(short or fullName) then
                skippedRecentGroup = skippedRecentGroup + 1
            elseif isBlocked(blocked, fullName) then
                skippedBlocked = skippedBlocked + 1
            elseif isFiltered(whoInfo, opts.terms) then
                skippedFilter = skippedFilter + 1
            elseif not isIncluded(whoInfo, opts.includeTerms) then
                skippedFilter = skippedFilter + 1
            elseif skip and skip[fullName:lower()] then
                skippedSkip = skippedSkip + 1
            elseif cooldownBucket and not isCool(cooldownBucket, fullName, opts.cooldownSeconds) then
                skippedCool = skippedCool + 1
            else
                eligible[#eligible + 1] = fullName
            end
        end
    end

    local eligibleCount = #eligible
    local sendCount = opts.limit and math.min(opts.limit, eligibleCount) or eligibleCount

    -- Counts behind the "N skipped" total, in the order the breakdown reads.
    local skipCounts = {
        blocked = skippedBlocked,
        skiplist = skippedSkip,
        cooldown = skippedCool,
        filter = skippedFilter,
        group = skippedGroup,
        recentGroup = skippedRecentGroup,
        limit = eligibleCount - sendCount,
    }

    if sendCount == 0 then
        local detail = "None of " .. count .. " /who " .. plural(count, "result", "results") .. " are eligible"
        local why = ns.SkipBreakdown(skipCounts)
        if why then detail = detail .. " (" .. why .. ")" end
        fail("Nobody to whisper.", detail .. ".")
        return
    end

    local skipped = count - sendCount

    -- Fold the count, skip breakdown, and list changes into one status line.
    local function summarize(lead)
        local line = lead .. " of " .. count .. " /who " .. plural(count, "result", "results")
        if skipped > 0 then
            line = line .. ", " .. tint("skip", skipped .. " skipped")
            local why = ns.SkipBreakdown(skipCounts)
            if why then line = line .. " (" .. why .. ")" end
        end
        local applied = ns.AppliedSummary(sendCount, skip ~= nil, cooldownMinutes)
        if applied then line = line .. ", " .. applied end
        return line
    end

    -- Summary first, so it leads the outgoing whisper lines; the queue confirms delivery by the server's echoes.
    status(summarize(tint("sent", "Whispering " .. sendCount)) .. ".")
    local sentNames = {}
    for i = 1, sendCount do
        local fullName = eligible[i]
        ns.QueueWhisper(opts.text, fullName)
        sentNames[#sentNames + 1] = fullName
        if skip then skip[fullName:lower()] = time() end
        -- Only a timed -cd records new recipients; bare -cd just reads the list.
        if cooldownBucket and cooldownMinutes then cooldownBucket[fullName] = time() end
    end

    -- /rr replies to these names once they whisper back.
    ns.TrackWhispered(sentNames)
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
    if opts.limitError then
        fail("-limit needs a number.", "e.g. /ww -limit 10 LFM SM live.")
        return
    end
    if opts.cdError then
        fail("-cd needs minutes as a number.", "\"" .. opts.cdError .. "\" isn't one. e.g. /ww -cd 30 WTB Black Lotus.")
        return
    end
    if opts.flagError then
        fail("Flags go before the message.", opts.flagError .. " would have been whispered as text. e.g. /ww -limit 10 LFM SM live.")
        return
    end
    if not opts.text or opts.text == "" then
        note("Usage: /ww MESSAGE — whisper everyone in your current /who results. e.g. /ww LFM SM live. Type /ss for all options.")
        return
    end
    if opts.wait then
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
    if opts.limitError then
        fail("-limit needs a number.", "e.g. /ws -limit 10 still selling?")
        return
    end
    if opts.cdError then
        fail("-cd needs minutes as a number.", "\"" .. opts.cdError .. "\" isn't one. e.g. /ws -cd 30 still selling?")
        return
    end
    if opts.flagError then
        fail("Flags go before the message.", opts.flagError .. " would have been whispered as text. e.g. /ws -limit 10 still selling?")
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

    local blocked = loadBlocked()
    local skip = opts.useSkip and loadSkip() or nil
    local cooldownBucket, cooldownMinutes
    if opts.useCooldown then
        cooldownBucket = loadCooldowns()
        if opts.cooldownSeconds then
            pruneCooldowns(cooldownBucket, opts.cooldownSeconds)
            cooldownMinutes = math.floor(opts.cooldownSeconds / 60)
        end
    end

    local total = #names
    local skippedBlocked, skippedSkip, skippedCool = 0, 0, 0
    local eligible = {}
    for _, sellerName in ipairs(names) do
        if isBlocked(blocked, sellerName) then
            skippedBlocked = skippedBlocked + 1
        elseif skip and skip[sellerName:lower()] then
            skippedSkip = skippedSkip + 1
        elseif cooldownBucket and not isCool(cooldownBucket, sellerName, opts.cooldownSeconds) then
            skippedCool = skippedCool + 1
        else
            eligible[#eligible + 1] = sellerName
        end
    end

    local eligibleCount = #eligible
    local sendCount = opts.limit and math.min(opts.limit, eligibleCount) or eligibleCount

    local skipCounts = {
        blocked = skippedBlocked,
        skiplist = skippedSkip,
        cooldown = skippedCool,
        limit = eligibleCount - sendCount,
    }

    if sendCount == 0 then
        local detail = "None of " .. total .. " " .. plural(total, "seller", "sellers") .. " are eligible"
        local why = ns.SkipBreakdown(skipCounts)
        if why then detail = detail .. " (" .. why .. ")" end
        fail("Nobody to whisper.", detail .. ".")
        return
    end

    local skipped = total - sendCount

    -- Fold the count, skip breakdown, and list changes into one status line.
    local function summarize(lead)
        local line = lead .. " of " .. total .. " " .. plural(total, "seller", "sellers")
        if skipped > 0 then
            line = line .. ", " .. tint("skip", skipped .. " skipped")
            local why = ns.SkipBreakdown(skipCounts)
            if why then line = line .. " (" .. why .. ")" end
        end
        local applied = ns.AppliedSummary(sendCount, skip ~= nil, cooldownMinutes)
        if applied then line = line .. ", " .. applied end
        return line
    end

    status(summarize(tint("sent", "Whispering " .. sendCount)) .. ".")
    for i = 1, sendCount do
        local sellerName = eligible[i]
        ns.QueueWhisper(opts.text, sellerName)
        if skip then skip[sellerName:lower()] = time() end
        -- Only a timed -cd records new recipients; bare -cd just reads the list.
        if cooldownBucket and cooldownMinutes then cooldownBucket[sellerName] = time() end
    end
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
        note("Usage: /ss -ignore NAME — add a player to the ignore list, or /ss -ignore clear to empty it.")
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

SLASH_WHISPERTARGET1 = "/wt"
SlashCmdList["WHISPERTARGET"] = whisperTarget

SLASH_WHISPERWHO1 = "/ww"
SlashCmdList["WHISPERWHO"] = whisperWho

SLASH_WHISPERSELLERS1 = "/ws"
SlashCmdList["WHISPERSELLERS"] = whisperSellers

SLASH_SUPERSOCIAL1 = "/ss"
SlashCmdList["SUPERSOCIAL"] = adminCommand
