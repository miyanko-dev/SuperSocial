local PREFIX = "|cffffff00[WhisperThemAll]:|r "

local function notify(msg)
    print(PREFIX .. msg)
end

local function loadIgnore()
    WhisperThemAllDB = WhisperThemAllDB or {}
    WhisperThemAllDB.ignored = WhisperThemAllDB.ignored or {}
    return WhisperThemAllDB.ignored
end

local function clearIgnore()
    local ignored = loadIgnore()
    if next(ignored) == nil then
        notify("ignore list is already empty.")
        return
    end
    wipe(ignored)
    notify("ignore list cleared.")
end

local function whisperTarget(text, remember)
    if not text or text == "" then
        notify("usage: /wt MESSAGE")
        return
    end
    if not (UnitExists("target") and UnitIsPlayer("target")) then
        notify("no valid player target.")
        return
    end
    local name = UnitName("target")
    local ignored = remember and loadIgnore() or nil
    if ignored and ignored[name] then
        notify(name .. " already contacted.")
        return
    end
    SendChatMessage(text, "WHISPER", nil, name)
    if ignored then ignored[name] = true end
end

local function parseWhoInput(input)
    local tokens = {}
    for token in input:gmatch("%S+") do
        tokens[#tokens + 1] = token
    end

    local cursor = 1
    local limit
    if tokens[cursor] and tokens[cursor]:match("^%d+$") then
        limit = tonumber(tokens[cursor])
        cursor = cursor + 1
    end

    local excludes = {}
    while tokens[cursor] and tokens[cursor]:sub(1, 1) == "-" and #tokens[cursor] > 1 do
        excludes[#excludes + 1] = tokens[cursor]:sub(2):lower()
        cursor = cursor + 1
    end

    local words = {}
    for i = cursor, #tokens do
        words[#words + 1] = tokens[i]
    end
    return limit, excludes, table.concat(words, " ")
end

local function isFiltered(info, excludes)
    if #excludes == 0 then return false end
    local class = (info.classStr or ""):lower()
    local area = (info.area or ""):lower()
    for _, filter in ipairs(excludes) do
        if filter == class then return true end
        if area ~= "" and area:find(filter, 1, true) then return true end
    end
    return false
end

local function whisperWho(input, remember)
    local limit, excludes, text = parseWhoInput(input or "")
    if text == "" then return end
    local count = C_FriendList.GetNumWhoResults()
    if count == 0 then return end
    limit = limit or count
    local ignored = remember and loadIgnore() or nil
    local sent = 0
    for i = 1, count do
        if sent >= limit then break end
        local info = C_FriendList.GetWhoInfo(i)
        if info and info.fullName
            and not isFiltered(info, excludes)
            and not (ignored and ignored[info.fullName]) then
            SendChatMessage(text, "WHISPER", nil, info.fullName)
            if ignored then ignored[info.fullName] = true end
            sent = sent + 1
        end
    end
end

local function getAuctionatorSellers()
    local ref = Auctionator and Auctionator.State and Auctionator.State.BuyFrameRef
    if not ref or not ref:IsShown() then return nil end
    local source = ref.CurrentPrices and ref.CurrentPrices.SearchDataProvider
    if not source or not source.allAuctions then return nil end
    local sellers = {}
    local me = UnitName("player")
    for _, auction in ipairs(source.allAuctions) do
        local name = tostring(auction.info[14])
        if name and name ~= "" and name ~= me then
            sellers[name] = true
        end
    end
    return sellers
end

local function getNativeSellers()
    local count = GetNumAuctionItems("list")
    if count == 0 then return nil end
    local sellers = {}
    local me = UnitName("player")
    for i = 1, count do
        local _, _, _, _, _, _, _, _, _, _, _, _, _, owner, ownerFullName = GetAuctionItemInfo("list", i)
        local name = ownerFullName or owner
        if name and name ~= "" and name ~= me then
            sellers[name] = true
        end
    end
    return sellers
end

local function whisperSellers(text)
    if not text or text == "" then
        notify("usage: /ws MESSAGE")
        return
    end
    if not AuctionFrame or not AuctionFrame:IsShown() then
        notify("auction house is not open.")
        return
    end
    local sellers = getAuctionatorSellers() or getNativeSellers()
    if not sellers or not next(sellers) then
        notify("no auction results.")
        return
    end
    local sent = 0
    for name in pairs(sellers) do
        SendChatMessage(text, "WHISPER", nil, name)
        sent = sent + 1
    end
    notify("whispered " .. sent .. " seller(s).")
end

local function blendWhisperColors()
    local outgoing = ChatTypeInfo["WHISPER_INFORM"]
    local incoming = ChatTypeInfo["WHISPER"]
    if not outgoing or not incoming then return end
    incoming.r = outgoing.r + (1 - outgoing.r) * 0.5
    incoming.g = outgoing.g + (1 - outgoing.g) * 0.5
    incoming.b = outgoing.b + (1 - outgoing.b) * 0.5
end

local colorWatch = CreateFrame("Frame")
colorWatch:RegisterEvent("PLAYER_ENTERING_WORLD")
colorWatch:RegisterEvent("UPDATE_CHAT_COLOR")
colorWatch:SetScript("OnEvent", blendWhisperColors)

SLASH_WHISPERTARGET1 = "/wt"
SlashCmdList["WHISPERTARGET"] = function(text) whisperTarget(text, false) end

SLASH_WHISPERTARGETPLUS1 = "/wt+"
SlashCmdList["WHISPERTARGETPLUS"] = function(text) whisperTarget(text, true) end

SLASH_WHISPERWHO1 = "/ww"
SlashCmdList["WHISPERWHO"] = function(input) whisperWho(input, false) end

SLASH_WHISPERWHOPLUS1 = "/ww+"
SlashCmdList["WHISPERWHOPLUS"] = function(input) whisperWho(input, true) end

SLASH_WHISPERCLEAR1 = "/w-clear"
SlashCmdList["WHISPERCLEAR"] = clearIgnore

SLASH_WHISPERSELLERS1 = "/ws"
SlashCmdList["WHISPERSELLERS"] = whisperSellers
