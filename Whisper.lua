local _, ns = ...

local applyingColor = false

local tint = ns.tint
local status, detail = ns.status, ns.detail
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
    if tokens[cursor] == "-skip" then
        useSkip = true
        cursor = cursor + 1
    end
    local text = table.concat(tokens, " ", cursor)
    if text == "" then return end
    if not (UnitExists("target") and UnitIsPlayer("target")) then
        status(tint("skip", "No player targeted") .. " — target someone first.")
        return
    end
    local targetName = UnitName("target")
    local _, classFile = UnitClass("target")
    SendChatMessage(text, "WHISPER", nil, targetName)
    status(tint("sent", "Whispered") .. " " .. className(targetName, classFile) .. ".")
    if useSkip then loadSkip()[targetName] = true end
end

local function parseFlags(input)
    local tokens = {}
    for t in input:gmatch("%S+") do tokens[#tokens + 1] = t end
    local cursor = 1
    local opts = { terms = {}, useSkip = false }
    while cursor <= #tokens do
        local flag = tokens[cursor]
        local value = tokens[cursor + 1]
        if flag:match("^%-%d+$") then
            opts.limit = tonumber(flag:sub(2))
            cursor = cursor + 1
        elseif flag == "-cd" then
            opts.useCooldown = true
            local minutes = value and tonumber(value)
            if minutes and minutes > 0 then
                opts.cooldownSeconds = math.floor(minutes * 60)
                cursor = cursor + 2
            else
                cursor = cursor + 1
            end
        elseif flag == "-skip" then
            opts.useSkip = true
            cursor = cursor + 1
        elseif flag == "-p" then
            opts.preview = true
            cursor = cursor + 1
        elseif flag == "-not" and value then
            local raw = value
            cursor = cursor + 2
            -- Keep absorbing tokens while the comma list is still open, so
            -- "-not Maraudon, Warlock" works with spaces around the commas.
            while cursor <= #tokens do
                local listContinues = raw:match(",%s*$") or tokens[cursor]:match("^,")
                if not listContinues then break end
                raw = raw .. " " .. tokens[cursor]
                cursor = cursor + 1
            end
            for term in raw:gmatch("[^,]+") do
                local cleaned = trim(term):lower()
                if cleaned ~= "" then
                    opts.terms[#opts.terms + 1] = cleaned
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

-- Shared with /rr so both commands parse flags and honour the same skip list
-- and cooldown pool identically.
ns.parseFlags = parseFlags
ns.loadSkip = loadSkip
ns.loadCooldowns = loadCooldowns
ns.pruneCooldowns = pruneCooldowns
ns.isCool = isCool

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

local CONFIRM_THRESHOLD = 30

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
        status(tint("skip", "No /who results") .. " — run /who first.")
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

    local eligible = {}
    for i = 1, count do
        local info = C_FriendList.GetWhoInfo(i)
        local fullName = info and info.fullName
        if fullName then
            local short = nameOnly(fullName)
            local excluded = groupSet[short or fullName]
                or isFiltered(info, opts.terms)
                or (skip and skip[fullName])
                or (cooldownBucket and not isCool(cooldownBucket, fullName, opts.cooldownSeconds))
            if not excluded then
                eligible[#eligible + 1] = fullName
            end
        end
    end

    local eligibleCount = #eligible
    local sendCount = opts.limit and math.min(opts.limit, eligibleCount) or eligibleCount

    if sendCount == 0 then
        status(tint("skip", "Nobody to whisper") .. " — 0 of " .. count .. " /who " .. plural(count, "result", "results") .. " eligible.")
        return
    end

    local skipped = count - sendCount

    if opts.preview then
        local line = tint("muted", "Preview") .. " — would whisper " .. sendCount .. " of " .. count .. " /who " .. plural(count, "result", "results")
        if skipped > 0 then
            line = line .. ", " .. tint("skip", skipped .. " skipped")
        end
        status(line .. ".")
        detail(tint("muted", "Message:") .. " " .. opts.text)
        return
    end

    -- Record skip-list / cooldown membership and queue the sends so they
    -- trickle out under the chat throttle.
    local function send()
        for i = 1, sendCount do
            local fullName = eligible[i]
            ns.queueWhisper(opts.text, fullName)
            if skip then skip[fullName] = true end
            -- Only a timed -cd records new recipients; bare -cd just reads the list.
            if cooldownBucket and cooldownMinutes then cooldownBucket[fullName] = time() end
        end

        local line = tint("sent", "Whispering " .. sendCount) .. " of " .. count .. " /who " .. plural(count, "result", "results")
        if skipped > 0 then
            line = line .. ", " .. tint("skip", skipped .. " skipped")
        end
        status(line .. ".")
    end

    confirmLargeSend(sendCount, send)
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

local function whisperSellers(input)
    input = trim(input)
    local preview = false
    if input == "-p" or input:match("^%-p%s") then
        preview = true
        input = trim(input:gsub("^%-p", "", 1))
    end
    local text = input
    if text == "" then return end
    if not AuctionFrame or not AuctionFrame:IsShown() then
        status(tint("skip", "Auction house closed") .. " — open the Browse tab first.")
        return
    end
    local names = collectAuctionSellers()
    if not names or #names == 0 then
        status(tint("skip", "No sellers") .. " in the current Browse results.")
        return
    end
    if preview then
        status(tint("muted", "Preview") .. " — would whisper " .. #names .. " auction " .. plural(#names, "seller", "sellers") .. ".")
        detail(tint("muted", "Message:") .. " " .. text)
        return
    end
    local function send()
        for _, sellerName in ipairs(names) do
            ns.queueWhisper(text, sellerName)
        end
        status(tint("sent", "Whispering " .. #names) .. " auction " .. plural(#names, "seller", "sellers") .. ".")
    end

    confirmLargeSend(#names, send)
end

local function adminCommand(input)
    input = trim(input):lower()
    if input == "" or input == "help" then
        ns.toggleHelp()
    elseif input == "stop" then
        local sent, dropped = ns.cancelQueue()
        if sent == 0 and dropped == 0 then
            status(tint("skip", "Nothing to stop") .. " — no whispers queued.")
        else
            status(tint("skip", "Stopped") .. " — " .. sent .. " sent, " .. dropped .. " " .. plural(dropped, "whisper", "whispers") .. " cancelled.")
        end
    elseif input == "reset" or input == "clear" then
        clearSkip()
        status(tint("skip", "Skip list cleared") .. ".")
    elseif input == "clear cd" then
        clearCooldowns()
        status(tint("cool", "Cooldown history cleared") .. ".")
    elseif input == "clear all" then
        clearSkip()
        clearCooldowns()
        status("Skip list and cooldown history cleared.")
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

