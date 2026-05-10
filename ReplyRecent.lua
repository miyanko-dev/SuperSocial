local YELLOW = "|cffffff00"
local RESET = "|r"

local MAX_RECENT = 80

local recentList = {}
local recentSet = {}
local repliedSet = {}

local function announce(msg)
    print(YELLOW .. "[GetInTouch]:" .. RESET .. " " .. msg)
end

local function replyRecent(input)
    local count, text = input:match("^(%d+)%s+(.+)$")
    if not text then
        text = input
        count = #recentList
    else
        count = tonumber(count)
    end
    if #recentList == 0 then
        announce("no players have whispered you yet.")
        return
    end
    if count and text and text ~= "" then
        local session = {}
        local start = math.max(#recentList - count + 1, 1)
        for i = start, #recentList do
            local name = recentList[i]
            if name and not session[name] and not repliedSet[name] then
                SendChatMessage(text, "WHISPER", nil, name)
                session[name] = true
                repliedSet[name] = true
            end
        end
    else
        announce("usage: /rr MESSAGE or /rr N MESSAGE")
    end
end

local function addRecent(name)
    if recentSet[name] then
        for i = 1, #recentList do
            if recentList[i] == name then
                table.remove(recentList, i)
                break
            end
        end
    else
        recentSet[name] = true
    end
    table.insert(recentList, name)
    while #recentList > MAX_RECENT do
        local removed = table.remove(recentList, 1)
        recentSet[removed] = nil
    end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("CHAT_MSG_WHISPER")
frame:SetScript("OnEvent", function(_, _, _, sender)
    addRecent(sender)
end)

SLASH_REPLYRECENT1 = "/rr"
SlashCmdList["REPLYRECENT"] = function(input)
    if input == "reset" then
        repliedSet = {}
        announce("reply list cleared.")
    else
        replyRecent(input)
    end
end
