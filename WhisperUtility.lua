local YELLOW = "|cffffff00"
local RESET = "|r"

local function announce(msg)
    print(YELLOW .. "[GetInTouch]:" .. RESET .. " " .. msg)
end

local function initIgnoreList()
    if not GetInTouchClassicDB then GetInTouchClassicDB = {} end
    if type(GetInTouchClassicDB.MultiWhisperIgnore) ~= "table" then
        GetInTouchClassicDB.MultiWhisperIgnore = {}
    end
end

local function resetIgnoreList()
    if GetInTouchClassicDB and GetInTouchClassicDB.MultiWhisperIgnore then
        GetInTouchClassicDB.MultiWhisperIgnore = {}
        announce("ignore list cleared.")
    else
        announce("ignore list is already empty.")
    end
end

local function whisperTarget(text)
    if not text or text == "" then
        announce("usage: /wt MESSAGE")
        return
    end
    if UnitExists("target") and UnitIsPlayer("target") then
        SendChatMessage(text, "WHISPER", nil, UnitName("target"))
    else
        announce("no valid player target.")
    end
end

local function whisperTargetOnce(text)
    if not text or text == "" then
        announce("usage: /wt-once MESSAGE")
        return
    end
    if UnitExists("target") and UnitIsPlayer("target") then
        local name = UnitName("target")
        initIgnoreList()
        if not GetInTouchClassicDB.MultiWhisperIgnore[name] then
            SendChatMessage(text, "WHISPER", nil, name)
            GetInTouchClassicDB.MultiWhisperIgnore[name] = true
        else
            announce(name .. " already contacted.")
        end
    else
        announce("no valid player target.")
    end
end

local function parseWhoParams(input)
    local limit, skip, text

    limit, skip, text = input:match("^(%d+)%s+%-(%w+)%s+(.+)$")
    if limit then return limit, skip, text end

    limit, text = input:match("^(%d+)%s+(.+)$")
    if limit then return limit, nil, text end

    skip, text = input:match("^%-(%w+)%s+(.+)$")
    if skip then return nil, skip, text end

    return nil, nil, input
end

local function whisperWho(input)
    if input:match("^%s*reset%s*$") then
        resetIgnoreList()
        return
    end
    local limit, skip, text = parseWhoParams(input)
    local count = C_FriendList.GetNumWhoResults()
    limit = limit and tonumber(limit) or count
    skip = skip and skip:lower() or nil
    if text and text ~= "" and count > 0 then
        local sent = 0
        for i = 1, count do
            if sent >= limit then break end
            local info = C_FriendList.GetWhoInfo(i)
            if info and info.fullName then
                if not skip or info.classStr:lower() ~= skip then
                    SendChatMessage(text, "WHISPER", nil, info.fullName)
                    sent = sent + 1
                end
            end
        end
    end
end

local function whisperWhoOnce(input)
    if input:match("^%s*reset%s*$") then
        resetIgnoreList()
        return
    end
    initIgnoreList()
    local limit, skip, text = parseWhoParams(input)
    local count = C_FriendList.GetNumWhoResults()
    limit = limit and tonumber(limit) or count
    skip = skip and skip:lower() or nil
    if text and text ~= "" and count > 0 then
        local sent = 0
        for i = 1, count do
            if sent >= limit then break end
            local info = C_FriendList.GetWhoInfo(i)
            if info and info.fullName then
                if (not skip or info.classStr:lower() ~= skip) and not GetInTouchClassicDB.MultiWhisperIgnore[info.fullName] then
                    SendChatMessage(text, "WHISPER", nil, info.fullName)
                    GetInTouchClassicDB.MultiWhisperIgnore[info.fullName] = true
                    sent = sent + 1
                end
            end
        end
    end
end

SLASH_WHISPERTARGET1 = "/wt"
SlashCmdList["WHISPERTARGET"] = whisperTarget

SLASH_WHISPERTARGET_SKIP1 = "/wt-once"
SlashCmdList["WHISPERTARGET_SKIP"] = whisperTargetOnce

SLASH_WHISPERWHO1 = "/ww"
SlashCmdList["WHISPERWHO"] = whisperWho

SLASH_WHISPERWHO_SKIP1 = "/ww-once"
SlashCmdList["WHISPERWHO_SKIP"] = whisperWhoOnce

local colorFrame = CreateFrame("Frame")
colorFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
colorFrame:RegisterEvent("UPDATE_CHAT_COLOR")
colorFrame:SetScript("OnEvent", function()
    local outgoing = ChatTypeInfo["WHISPER_INFORM"]
    if not outgoing then return end
    local incoming = ChatTypeInfo["WHISPER"]
    if not incoming then return end
    incoming.r = outgoing.r + (1 - outgoing.r) * 0.5
    incoming.g = outgoing.g + (1 - outgoing.g) * 0.5
    incoming.b = outgoing.b + (1 - outgoing.b) * 0.5
end)

hooksecurefunc("ChatEdit_UpdateHeader", function(editBox)
    if editBox:GetAttribute("chatType") == "WHISPER" then
        local info = ChatTypeInfo["WHISPER_INFORM"]
        if not info then return end
        editBox:SetTextColor(info.r, info.g, info.b)
        if editBox.header then
            editBox.header:SetTextColor(info.r, info.g, info.b)
        end
    end
end)
