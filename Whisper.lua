local _, ns = ...

local applyingColor = false

local tint = ns.tint
local status = ns.status
local plural = ns.plural
local className = ns.className

local function trim(s)
    return (s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function playerKey()
    return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
end

local function loadSkip()
    WhisperThemAllDB = WhisperThemAllDB or {}

    -- One account-wide ignore list shared by every character.
    local bucket = WhisperThemAllDB.ignoredAccount or {}
    WhisperThemAllDB.ignoredAccount = bucket

    -- Migrate per-character buckets into the shared list.
    if WhisperThemAllDB.ignoredByChar then
        for _, charBucket in pairs(WhisperThemAllDB.ignoredByChar) do
            for name in pairs(charBucket) do
                bucket[name] = true
            end
        end
        WhisperThemAllDB.ignoredByChar = nil
    end

    -- Migrate the pre-per-char flat list as well.
    if WhisperThemAllDB.ignored then
        for name in pairs(WhisperThemAllDB.ignored) do
            bucket[name] = true
        end
        WhisperThemAllDB.ignored = nil
    end

    return bucket
end

local function clearSkip()
    wipe(loadSkip())
end

local function loadCooldowns()
    WhisperThemAllDB = WhisperThemAllDB or {}
    WhisperThemAllDB.cooldownByChar = WhisperThemAllDB.cooldownByChar or {}
    local key = playerKey()
    local bucket = WhisperThemAllDB.cooldownByChar[key] or {}
    WhisperThemAllDB.cooldownByChar[key] = bucket
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

ns.nameOnly = nameOnly
ns.buildGroupSet = buildGroupSet

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
    local text = table.concat(tokens, " ", cursor)
    if text == "" then
        status(tint("muted", "Usage:") .. " /wt MESSAGE — whisper your current target ("
            .. tint("muted", "-ignore") .. " also adds them to the ignore list). "
            .. tint("muted", "e.g.") .. " " .. tint("cool", "/wt got room for one more?") .. ".")
        return
    end
    if not (UnitExists("target") and UnitIsPlayer("target")) then
        status(tint("skip", "No target selected.") .. " Pick a player first and I'll whisper them.")
        return
    end
    local targetName = UnitName("target")
    local _, classFile = UnitClass("target")
    SendChatMessage(text, "WHISPER", nil, targetName)
    status(tint("sent", "Whispered") .. " " .. className(targetName, classFile) .. ".")
    if useSkip then loadSkip()[targetName] = true end
end

-- "instance" inside -skip or -only expands to these, so one word covers anyone
-- already inside a dungeon or raid. Distinctive substrings of the English
-- zone names; "ahn'qiraj" catches both the Ruins and the Temple.
local INSTANCE_TERMS = {
    "ragefire chasm", "wailing caverns", "deadmines", "shadowfang keep",
    "stockade", "blackfathom deeps", "gnomeregan", "razorfen kraul",
    "scarlet monastery", "razorfen downs", "uldaman", "zul'farrak",
    "maraudon", "atal'hakkar", "blackrock depths", "blackrock spire",
    "dire maul", "scholomance", "stratholme",
    "molten core", "onyxia's lair", "blackwing lair", "zul'gurub",
    "ahn'qiraj", "naxxramas",
}

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
                -- No positive number after it: flag the mistake so the caller can
                -- nudge instead of silently whispering everyone.
                opts.limitError = true
                cursor = cursor + 1
            end
        elseif flag == "-cd" then
            opts.useCooldown = true
            local minutes = value and tonumber(value)
            if minutes and minutes > 0 then
                opts.cooldownSeconds = math.floor(minutes * 60)
                cursor = cursor + 2
            else
                cursor = cursor + 1
            end
        elseif flag == "-ignore" then
            opts.useSkip = true
            cursor = cursor + 1
        elseif (flag == "-skip" or flag == "-only") and value then
            local bucket = (flag == "-only") and opts.includeTerms or opts.terms
            local raw = value
            cursor = cursor + 2
            -- Keep absorbing tokens while the comma list is still open, so
            -- "-skip Maraudon, Warlock" works with spaces around the commas.
            while cursor <= #tokens do
                local listContinues = raw:match(",%s*$") or tokens[cursor]:match("^,")
                if not listContinues then break end
                raw = raw .. " " .. tokens[cursor]
                cursor = cursor + 1
            end
            for term in raw:gmatch("[^,]+") do
                local cleaned = trim(term):lower()
                if cleaned == "instance" then
                    for _, zone in ipairs(INSTANCE_TERMS) do
                        bucket[#bucket + 1] = zone
                    end
                elseif cleaned ~= "" then
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
    return opts
end

-- Shared with /rr so both commands parse flags and honour the same ignore list
-- and cooldown pool identically.
ns.parseFlags = parseFlags
ns.loadSkip = loadSkip
ns.loadCooldowns = loadCooldowns
ns.pruneCooldowns = pruneCooldowns
ns.isCool = isCool

-- A term matches a player when it's a substring of their class or their zone,
-- so "war" catches both Warriors and Warsong Gulch.
local function matchesTerm(info, term)
    local class = (info.classStr or ""):lower()
    local area = (info.area or ""):lower()
    if class ~= "" and class:find(term, 1, true) then return true end
    if area ~= "" and area:find(term, 1, true) then return true end
    return false
end

local function isFiltered(info, terms)
    for _, term in ipairs(terms) do
        if matchesTerm(info, term) then return true end
    end
    return false
end

-- -only is the inverse of -skip: with terms set, a player must match at least
-- one term to qualify. No terms = everyone.
local function isIncluded(info, includeTerms)
    if #includeTerms == 0 then return true end
    for _, term in ipairs(includeTerms) do
        if matchesTerm(info, term) then return true end
    end
    return false
end

local CONFIRM_THRESHOLD = 20

StaticPopupDialogs["WHISPERTHEMALL_CONFIRM_SEND"] = {
    text = "Whisper Them All: send to %d players?",
    button1 = YES,
    button2 = NO,
    OnAccept = function(_, send) if send then send() end end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    showAlert = true,
    preferredIndex = 3,
}

-- Big bulk sends ask first, so a near-full /who or Browse list can't go out by
-- accident. Smaller runs send straight away.
local function confirmLargeSend(count, send)
    if count <= CONFIRM_THRESHOLD then
        send()
    else
        StaticPopup_Show("WHISPERTHEMALL_CONFIRM_SEND", count, nil, send)
    end
end

local function dispatchWho(opts)
    local count = C_FriendList.GetNumWhoResults()
    if count == 0 then
        status(tint("skip", "No /who results yet.") .. " Run /who first and I'll whisper them.")
        return
    end

    local groupSet = buildGroupSet()
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

    local skippedGroup, skippedFilter, skippedSkip, skippedCool = 0, 0, 0, 0
    local eligible = {}
    for i = 1, count do
        local info = C_FriendList.GetWhoInfo(i)
        local fullName = info and info.fullName
        if fullName then
            local short = nameOnly(fullName)
            if groupSet[short or fullName] then
                skippedGroup = skippedGroup + 1
            elseif isFiltered(info, opts.terms) then
                skippedFilter = skippedFilter + 1
            elseif not isIncluded(info, opts.includeTerms) then
                skippedFilter = skippedFilter + 1
            elseif skip and skip[fullName] then
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
        skiplist = skippedSkip,
        cooldown = skippedCool,
        filter = skippedFilter,
        group = skippedGroup,
        limit = eligibleCount - sendCount,
    }

    if sendCount == 0 then
        local line = tint("skip", "Nobody to whisper.") .. " None of " .. count .. " /who " .. plural(count, "result", "results") .. " are eligible"
        local why = ns.skipBreakdown(skipCounts)
        if why then line = line .. " (" .. why .. ")" end
        status(line .. ".")
        return
    end

    local skipped = count - sendCount

    -- Fold the count, skip breakdown, and list changes into one status line.
    local function summarize(lead)
        local line = lead .. " of " .. count .. " /who " .. plural(count, "result", "results")
        if skipped > 0 then
            line = line .. ", " .. tint("skip", skipped .. " skipped")
            local why = ns.skipBreakdown(skipCounts)
            if why then line = line .. " (" .. why .. ")" end
        end
        local applied = ns.appliedSummary(sendCount, skip ~= nil, cooldownMinutes)
        if applied then line = line .. ", " .. applied end
        return line
    end

    -- Summary first, so it leads the outgoing whisper lines; the queue then
    -- trickles them out under the chat throttle.
    local function send()
        status(summarize(tint("sent", "Whispering " .. sendCount)) .. ".")
        local sentNames = {}
        for i = 1, sendCount do
            local fullName = eligible[i]
            ns.queueWhisper(opts.text, fullName)
            sentNames[#sentNames + 1] = fullName
            if skip then skip[fullName] = true end
            -- Only a timed -cd records new recipients; bare -cd just reads the list.
            if cooldownBucket and cooldownMinutes then cooldownBucket[fullName] = time() end
        end
        -- This blast becomes the /rr batch: replies from these names feed /rr.
        ns.beginReplyBatch(sentNames)
    end

    confirmLargeSend(sendCount, send)
end

local function whisperWho(input)
    local opts = parseFlags(trim(input))
    if opts.limitError then
        status(tint("skip", "-limit needs a number.") .. " " .. tint("muted", "e.g.") .. " " .. tint("cool", "/ww -limit 10 LFM SM live") .. ".")
        return
    end
    if not opts.text or opts.text == "" then
        status(tint("muted", "Usage:") .. " /ww MESSAGE — whisper everyone in your current /who results. "
            .. tint("muted", "e.g.") .. " " .. tint("cool", "/ww LFM SM live") .. ".  Type /wta for all options.")
        return
    end
    dispatchWho(opts)
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
        status(tint("skip", "-limit needs a number.") .. " " .. tint("muted", "e.g.") .. " " .. tint("cool", "/ws -limit 10 still selling?") .. ".")
        return
    end
    -- Sellers carry no class or zone, so the term filters can't apply here.
    if #opts.terms > 0 or #opts.includeTerms > 0 then
        status(tint("skip", "-skip and -only don't apply to /ws.") .. " Sellers carry no class or zone data.")
        return
    end
    if not opts.text or opts.text == "" then
        status(tint("muted", "Usage:") .. " /ws MESSAGE — whisper every seller in the auction house Browse tab. "
            .. tint("muted", "e.g.") .. " " .. tint("cool", "/ws still selling your Black Lotus?") .. ".")
        return
    end
    if not AuctionFrame or not AuctionFrame:IsShown() then
        status(tint("skip", "Auction house closed.") .. " Open the Browse tab and I'll whisper the sellers.")
        return
    end
    local names = collectAuctionSellers()
    if not names or #names == 0 then
        status(tint("skip", "No sellers") .. " in the current Browse results.")
        return
    end

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
    local skippedSkip, skippedCool = 0, 0
    local eligible = {}
    for _, sellerName in ipairs(names) do
        if skip and skip[sellerName] then
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
        skiplist = skippedSkip,
        cooldown = skippedCool,
        limit = eligibleCount - sendCount,
    }

    if sendCount == 0 then
        local line = tint("skip", "Nobody to whisper.") .. " None of " .. total .. " " .. plural(total, "seller", "sellers") .. " are eligible"
        local why = ns.skipBreakdown(skipCounts)
        if why then line = line .. " (" .. why .. ")" end
        status(line .. ".")
        return
    end

    local skipped = total - sendCount

    -- Fold the count, skip breakdown, and list changes into one status line.
    local function summarize(lead)
        local line = lead .. " of " .. total .. " " .. plural(total, "seller", "sellers")
        if skipped > 0 then
            line = line .. ", " .. tint("skip", skipped .. " skipped")
            local why = ns.skipBreakdown(skipCounts)
            if why then line = line .. " (" .. why .. ")" end
        end
        local applied = ns.appliedSummary(sendCount, skip ~= nil, cooldownMinutes)
        if applied then line = line .. ", " .. applied end
        return line
    end

    local function send()
        status(summarize(tint("sent", "Whispering " .. sendCount)) .. ".")
        for i = 1, sendCount do
            local sellerName = eligible[i]
            ns.queueWhisper(opts.text, sellerName)
            if skip then skip[sellerName] = true end
            -- Only a timed -cd records new recipients; bare -cd just reads the list.
            if cooldownBucket and cooldownMinutes then cooldownBucket[sellerName] = time() end
        end
    end

    confirmLargeSend(sendCount, send)
end

local function adminCommand(input)
    input = trim(input):lower()
    if input == "" or input == "help" then
        ns.toggleHelp()
    elseif input == "stop" then
        local sent, dropped = ns.cancelQueue()
        if sent == 0 and dropped == 0 then
            status(tint("skip", "Nothing to stop.") .. " No whispers are queued.")
        else
            status(tint("skip", "Stopped.") .. " " .. sent .. " sent, " .. dropped .. " " .. plural(dropped, "whisper", "whispers") .. " cancelled.")
        end
    elseif input == "reset" or input == "clear" then
        clearSkip()
        status(tint("skip", "Ignore list cleared") .. ".")
    elseif input == "clear cd" then
        clearCooldowns()
        status(tint("cool", "Cooldown history cleared") .. ".")
    elseif input == "clear all" then
        clearSkip()
        clearCooldowns()
        status("Ignore list and cooldown history cleared.")
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

SLASH_WHISPERTHEMALLADMIN1 = "/wta"
SlashCmdList["WHISPERTHEMALLADMIN"] = adminCommand

