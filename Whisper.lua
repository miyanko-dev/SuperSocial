local applyingColor = false

local CHAT_PREFIX = "|cff66ccffWhisperThemAll:|r "

local function chatLine(text)
    DEFAULT_CHAT_FRAME:AddMessage(CHAT_PREFIX .. text)
end

local function trim(s)
    return (s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function plural(n, singular, multiple)
    if n == 1 then return singular end
    return multiple
end

local function playerKey()
    return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
end

local function loadSkip()
    WhisperThemAllDB = WhisperThemAllDB or {}
    WhisperThemAllDB.ignoredByChar = WhisperThemAllDB.ignoredByChar or {}
    local key = playerKey()
    local bucket = WhisperThemAllDB.ignoredByChar[key] or {}
    WhisperThemAllDB.ignoredByChar[key] = bucket

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

local function whisperTarget(input)
    input = trim(input or "")
    local tokens = {}
    for t in input:gmatch("%S+") do tokens[#tokens + 1] = t end
    local cursor = 1
    local useSkip = false
    if tokens[cursor] == "-skip" then
        useSkip = true
        cursor = cursor + 1
    end
    local text = table.concat(tokens, " ", cursor)
    if text == "" then return end
    if not (UnitExists("target") and UnitIsPlayer("target")) then return end
    local name = UnitName("target")
    SendChatMessage(text, "WHISPER", nil, name)
    if useSkip then loadSkip()[name] = true end
end

local function parseFlags(input)
    local tokens = {}
    for t in input:gmatch("%S+") do tokens[#tokens + 1] = t end
    local cursor = 1
    local opts = { terms = {}, useSkip = false }
    while cursor <= #tokens do
        local flag = tokens[cursor]
        local value = tokens[cursor + 1]
        if flag == "-limit" and value then
            opts.limit = tonumber(value)
            cursor = cursor + 2
        elseif flag == "-cd" and value then
            local minutes = tonumber(value)
            if minutes and minutes > 0 then
                opts.cooldownSeconds = math.floor(minutes * 60)
            end
            cursor = cursor + 2
        elseif flag == "-skip" then
            opts.useSkip = true
            cursor = cursor + 1
        elseif flag == "-not" and value then
            for term in value:gmatch("[^,]+") do
                local cleaned = trim(term):lower()
                if cleaned ~= "" then
                    opts.terms[#opts.terms + 1] = cleaned
                end
            end
            cursor = cursor + 2
        else
            break
        end
    end
    local words = {}
    for i = cursor, #tokens do words[#words + 1] = tokens[i] end
    opts.text = table.concat(words, " ")
    return opts
end

local function isFiltered(info, terms)
    if #terms == 0 then return false end
    local class = (info.classStr or ""):lower()
    local area = (info.area or ""):lower()
    for _, term in ipairs(terms) do
        if term == class then return true end
        if area ~= "" and area:find(term, 1, true) then return true end
    end
    return false
end

local function dispatchWho(opts)
    local count = C_FriendList.GetNumWhoResults()
    if count == 0 then
        chatLine("No /who results — run /who first.")
        return
    end

    local groupSet = buildGroupSet()
    local skip = opts.useSkip and loadSkip() or nil
    local cooldownBucket
    local cooldownMinutes
    if opts.cooldownSeconds then
        cooldownBucket = loadCooldowns()
        pruneCooldowns(cooldownBucket, opts.cooldownSeconds)
        cooldownMinutes = math.floor(opts.cooldownSeconds / 60)
    end

    local eligible = {}
    local skipGroup, skipNot, skipList, skipCd = 0, 0, 0, 0
    for i = 1, count do
        local info = C_FriendList.GetWhoInfo(i)
        local fullName = info and info.fullName
        if fullName then
            local short = nameOnly(fullName)
            if groupSet[short or fullName] then
                skipGroup = skipGroup + 1
            elseif isFiltered(info, opts.terms) then
                skipNot = skipNot + 1
            elseif skip and skip[fullName] then
                skipList = skipList + 1
            elseif cooldownBucket and not isCool(cooldownBucket, fullName, opts.cooldownSeconds) then
                skipCd = skipCd + 1
            else
                eligible[#eligible + 1] = fullName
            end
        end
    end

    local eligibleCount = #eligible
    local sendCount = opts.limit and math.min(opts.limit, eligibleCount) or eligibleCount
    local skipLimit = eligibleCount - sendCount
    local skippedTotal = skipGroup + skipNot + skipList + skipCd + skipLimit

    if sendCount == 0 then
        chatLine("0 of " .. count .. " /who " .. plural(count, "result", "results") .. " eligible to whisper.")
        local parts = {}
        if skipGroup > 0 then parts[#parts + 1] = "party/raid " .. skipGroup end
        if skipNot > 0 then parts[#parts + 1] = "-not " .. skipNot end
        if skipList > 0 then parts[#parts + 1] = "-skip " .. skipList end
        if skipCd > 0 then parts[#parts + 1] = "-cd " .. skipCd end
        if #parts > 0 then chatLine("Skipped: " .. table.concat(parts, ", ") .. ".") end
        return
    end

    chatLine("Whispering " .. sendCount .. " of " .. count .. " /who " .. plural(count, "result", "results") .. ".")
    if skipLimit > 0 then
        chatLine("  -limit " .. opts.limit .. " — capping " .. skipLimit .. " eligible " .. plural(skipLimit, "recipient", "recipients") .. ".")
    end
    if #opts.terms > 0 then
        chatLine("  -not " .. table.concat(opts.terms, ",") .. " — skipping " .. skipNot .. " matching class/zone.")
    end
    if skip then
        chatLine("  -skip — skipping " .. skipList .. " already on the skip list; new recipients will be added.")
    end
    if cooldownBucket then
        chatLine("  -cd " .. cooldownMinutes .. " — skipping " .. skipCd .. " still cooling; new recipients will cool for " .. cooldownMinutes .. " min.")
    end

    local addedSkip = 0
    for i = 1, sendCount do
        local fullName = eligible[i]
        SendChatMessage(opts.text, "WHISPER", nil, fullName)
        if skip and not skip[fullName] then
            skip[fullName] = true
            addedSkip = addedSkip + 1
        end
        if cooldownBucket then cooldownBucket[fullName] = time() end
    end

    if skippedTotal == 0 then
        chatLine("Sent " .. sendCount .. " " .. plural(sendCount, "whisper", "whispers") .. ".")
    else
        local parts = {}
        if skipGroup > 0 then parts[#parts + 1] = "party/raid " .. skipGroup end
        if skipNot > 0 then parts[#parts + 1] = "-not " .. skipNot end
        if skipList > 0 then parts[#parts + 1] = "-skip " .. skipList end
        if skipCd > 0 then parts[#parts + 1] = "-cd " .. skipCd end
        if skipLimit > 0 then parts[#parts + 1] = "-limit " .. skipLimit end
        chatLine("Sent " .. sendCount .. ". Skipped " .. skippedTotal .. " (" .. table.concat(parts, ", ") .. ").")
    end
    if skip and addedSkip > 0 then
        local total = 0
        for _ in pairs(skip) do total = total + 1 end
        chatLine("  +" .. addedSkip .. " added to skip list (now " .. total .. ").")
    end
    if cooldownBucket and sendCount > 0 then
        chatLine("  +" .. sendCount .. " on cooldown for " .. cooldownMinutes .. " min.")
    end
end

local function whisperWho(input)
    local opts = parseFlags(trim(input))
    if not opts.text or opts.text == "" then return end
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

local function whisperSellers(text)
    if not text or text == "" then return end
    if not AuctionFrame or not AuctionFrame:IsShown() then return end
    local names = collectAuctionSellers()
    if not names or #names == 0 then return end
    for _, name in ipairs(names) do
        SendChatMessage(text, "WHISPER", nil, name)
    end
end

local COMMANDS_HELP = {
    "|cffffd200/ww MESSAGE|r — Whisper everyone in your /who results.",
    "|cffffd200/wt MESSAGE|r — Whisper your current target.",
    "|cffffd200/ws MESSAGE|r — Whisper every seller in the auction house Browse tab.",
    "|cffffd200/rr MESSAGE|r — Reply to recent whisperers. Use \"/rr reset\" to clear the tracker.",
    "|cffffd200/wta|r — Print this help.",
    "|cffffd200/wta clear skip|r — Empty the skip list.",
    "|cffffd200/wta clear cd|r — Empty the cooldown history.",
    "|cffffd200/wta clear all|r — Empty both.",
}

local PARAMETERS_HELP = {
    "|cffffd200-limit N|r — Cap the recipient count to N.",
    "|cffffd200-not VALUE|r — Skip a class (Warrior, Mage, …) or a zone (substring match). Separate multiple values with commas.",
    "|cffffd200-skip|r — Skip anyone on the skip list, and add successful recipients to it.",
    "|cffffd200-cd M|r — Skip anyone whispered in the last M minutes, and remember new recipients for M minutes.",
}

local function printHelp()
    chatLine("Commands")
    for _, line in ipairs(COMMANDS_HELP) do
        DEFAULT_CHAT_FRAME:AddMessage("  " .. line)
    end
    chatLine("Parameters for /ww and /wt")
    for _, line in ipairs(PARAMETERS_HELP) do
        DEFAULT_CHAT_FRAME:AddMessage("  " .. line)
    end
end

local function adminCommand(input)
    input = trim(input):lower()
    if input == "" then
        printHelp()
    elseif input == "clear skip" then
        clearSkip()
    elseif input == "clear cd" then
        clearCooldowns()
    elseif input == "clear all" then
        clearSkip()
        clearCooldowns()
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

