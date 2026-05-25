local PREFIX = "|cffffff00[Whisper Them All!]:|r "
local COOLDOWN_SECONDS = 5 * 60

local applyingColor = false

local function notify(msg)
    print(PREFIX .. msg)
end

local function announce(count)
    notify(string.format("Sending message to %d player%s.", count, count == 1 and "" or "s"))
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
    local skip = loadSkip()
    if next(skip) == nil then
        notify("Skip list is already empty.")
        return
    end
    wipe(skip)
    notify("Skip list cleared.")
end

local function loadCooldowns()
    WhisperThemAllDB = WhisperThemAllDB or {}
    WhisperThemAllDB.cooldownByChar = WhisperThemAllDB.cooldownByChar or {}
    local key = playerKey()
    local bucket = WhisperThemAllDB.cooldownByChar[key] or {}
    WhisperThemAllDB.cooldownByChar[key] = bucket
    return bucket
end

local function pruneCooldowns(bucket)
    local cutoff = time() - COOLDOWN_SECONDS
    for n, ts in pairs(bucket) do
        if ts < cutoff then bucket[n] = nil end
    end
end

local function isCool(bucket, name)
    local ts = bucket[name]
    if not ts then return true end
    return (time() - ts) >= COOLDOWN_SECONDS
end

local function nameOnly(value)
    if not value then return nil end
    return value:match("^([^-]+)") or value
end

local function buildGroupSet()
    local set = {}
    if not IsInGroup() then return set end
    local me = UnitName("player")
    if me then set[me] = true end
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

local function whisperTarget(text)
    if not text or text == "" then
        notify("Usage: /wt MESSAGE")
        return
    end
    if not (UnitExists("target") and UnitIsPlayer("target")) then
        notify("No valid player target.")
        return
    end
    SendChatMessage(text, "WHISPER", nil, UnitName("target"))
end

local function whisperTargetPlus(text)
    if not text or text == "" then
        notify("Usage: /wt+ MESSAGE")
        return
    end
    if not (UnitExists("target") and UnitIsPlayer("target")) then
        notify("No valid player target.")
        return
    end
    local name = UnitName("target")
    SendChatMessage(text, "WHISPER", nil, name)
    local skip = loadSkip()
    skip[name] = true
end

-- Consume leading dash-prefixed options. -<number> sets the cap; -<text>
-- contributes to the exclude list. The first non-dash token starts MESSAGE.
local function parseDashOptions(input)
    local tokens = {}
    for t in input:gmatch("%S+") do tokens[#tokens + 1] = t end
    local cursor = 1
    local limit
    local excludes = {}
    while tokens[cursor] and tokens[cursor]:sub(1, 1) == "-" and #tokens[cursor] > 1 do
        local val = tokens[cursor]:sub(2)
        if val:match("^%d+$") then
            limit = tonumber(val)
        else
            excludes[#excludes + 1] = val:lower()
        end
        cursor = cursor + 1
    end
    local words = {}
    for i = cursor, #tokens do words[#words + 1] = tokens[i] end
    return limit, excludes, table.concat(words, " ")
end

local function isFiltered(info, excludes)
    if not excludes or #excludes == 0 then return false end
    local class = (info.classStr or ""):lower()
    local area = (info.area or ""):lower()
    local raw = (info.fullName or ""):lower()
    local name = raw:match("^([^-]+)") or raw
    for _, f in ipairs(excludes) do
        if f == class then return true end
        if area ~= "" and area:find(f, 1, true) then return true end
        if name ~= "" and name:find(f, 1, true) then return true end
    end
    return false
end

local function dispatchWho(limit, excludes, text, opts)
    local count = C_FriendList.GetNumWhoResults()
    if count == 0 then
        notify("No /who results.")
        return
    end
    limit = limit or count
    local groupSet = buildGroupSet()
    local skip = opts.useSkip and loadSkip() or nil
    local cooldownBucket
    if opts.useCooldown then
        cooldownBucket = loadCooldowns()
        pruneCooldowns(cooldownBucket)
    end

    local sent = 0
    for i = 1, count do
        if sent >= limit then break end
        local info = C_FriendList.GetWhoInfo(i)
        local fullName = info and info.fullName
        local short = nameOnly(fullName)
        local skipThis = not fullName
        if not skipThis and isFiltered(info, excludes) then skipThis = true end
        if not skipThis and groupSet[short or fullName] then skipThis = true end
        if not skipThis and skip and skip[fullName] then skipThis = true end
        if not skipThis and cooldownBucket and not isCool(cooldownBucket, fullName) then skipThis = true end
        if not skipThis then
            SendChatMessage(text, "WHISPER", nil, fullName)
            if skip then skip[fullName] = true end
            if cooldownBucket then cooldownBucket[fullName] = time() end
            sent = sent + 1
        end
    end
    if sent == 0 then
        notify("No recipients after filtering.")
    else
        announce(sent)
    end
end

local function whisperWho(input)
    input = (input or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local limit, excludes, text = parseDashOptions(input)
    if not text or text == "" then
        notify("Usage: /ww [-N] [-FILTER...] MESSAGE")
        return
    end
    dispatchWho(limit, excludes, text, { useSkip = false, useCooldown = true })
end

local function whisperWhoPlus(input)
    input = (input or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local limit, excludes, text = parseDashOptions(input)
    if not text or text == "" then
        notify("Usage: /ww+ [-N] [-FILTER...] MESSAGE")
        return
    end
    dispatchWho(limit, excludes, text, { useSkip = true, useCooldown = false })
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
    if not text or text == "" then
        notify("Usage: /ws MESSAGE")
        return
    end
    if not AuctionFrame or not AuctionFrame:IsShown() then
        notify("Open the auction house Browse tab and run a search first.")
        return
    end
    local names = collectAuctionSellers()
    if not names or #names == 0 then
        notify("No auction results -- run a search on the Browse tab first.")
        return
    end
    for _, name in ipairs(names) do
        SendChatMessage(text, "WHISPER", nil, name)
    end
    announce(#names)
end

local HELP_LINES = {
    { "/wt MESSAGE",                       "Whisper your current target." },
    { "/wt+ MESSAGE",                      "Whisper your current target and add them to the skip list." },
    { "/ww [-N] [-FILTER...] MESSAGE",     "Whisper everyone in your /who results. 5-minute cooldown per name." },
    { "/ww+ [-N] [-FILTER...] MESSAGE",    "Whisper /who results, skip anyone on the skip list, and add new recipients to it." },
    { "/ws MESSAGE",                       "Whisper every seller in the auction house Browse tab." },
    { "/rr [-N] MESSAGE",                  "Reply to the last whisperers." },
    { "/rr reset",                         "Clear the session reply-tracking list." },
    { "/port [N] ZONE",                    "Whisper mages and warlocks for a portal or summon (with confirmation)." },
    { "/clickers [N] ZONE [MESSAGE]",      "Whisper players to help click a summon (with confirmation). Alias: /clicker" },
    { "/wta",                              "Show this commands list." },
    { "/wta clear",                        "Clear the skip list." },
}

local function buildHelpText()
    local out = {}
    for i = 1, #HELP_LINES do
        local cmd, desc = HELP_LINES[i][1], HELP_LINES[i][2]
        out[#out + 1] = "|cffffd200" .. cmd .. "|r"
        out[#out + 1] = "|cffd0d0d0" .. desc .. "|r"
        if i < #HELP_LINES then out[#out + 1] = "" end
    end
    return table.concat(out, "\n")
end

local helpFrame

local function buildHelpFrame()
    local width, padX, topPad, bottomPad = 460, 14, 36, 14

    local f = CreateFrame("Frame", "WhisperThemAllHelpFrame", UIParent, "TooltipBorderedFrameTemplate")
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)

    local title = f:CreateFontString(nil, "OVERLAY", "GameTooltipHeaderText")
    title:SetPoint("TOPLEFT", padX, -12)
    title:SetJustifyH("LEFT")
    title:SetText("Whisper Them All!")

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)

    local body = f:CreateFontString(nil, "OVERLAY", "GameTooltipText")
    body:SetPoint("TOPLEFT", padX, -topPad)
    body:SetWidth(width - padX * 2)
    body:SetJustifyH("LEFT")
    body:SetJustifyV("TOP")
    body:SetSpacing(2)
    body:SetText(buildHelpText())

    f:SetSize(width, topPad + body:GetStringHeight() + bottomPad)

    tinsert(UISpecialFrames, "WhisperThemAllHelpFrame")
    f:Hide()
    return f
end

local function showHelp()
    if not helpFrame then helpFrame = buildHelpFrame() end
    helpFrame:Show()
    helpFrame:Raise()
end

local function adminCommand(input)
    input = (input or ""):gsub("^%s+", ""):gsub("%s+$", ""):lower()
    if input == "" then
        showHelp()
    elseif input == "clear" then
        clearSkip()
    else
        notify("Usage: /wta  or  /wta clear")
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
SlashCmdList["WHISPERTARGET"] = function(text) whisperTarget(text or "") end

SLASH_WHISPERTARGETPLUS1 = "/wt+"
SlashCmdList["WHISPERTARGETPLUS"] = function(text) whisperTargetPlus(text or "") end

SLASH_WHISPERWHO1 = "/ww"
SlashCmdList["WHISPERWHO"] = whisperWho

SLASH_WHISPERWHOPLUS1 = "/ww+"
SlashCmdList["WHISPERWHOPLUS"] = whisperWhoPlus

SLASH_WHISPERSELLERS1 = "/ws"
SlashCmdList["WHISPERSELLERS"] = whisperSellers

SLASH_WHISPERTHEMALLADMIN1 = "/wta"
SlashCmdList["WHISPERTHEMALLADMIN"] = adminCommand

_G.WhisperThemAll = _G.WhisperThemAll or {}
WhisperThemAll.BuildGroupSet = buildGroupSet
WhisperThemAll.NameOnly = nameOnly
WhisperThemAll.Announce = announce
