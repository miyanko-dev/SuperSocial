local PREFIX = "|cffffff00[WhisperThemAll]:|r "
local MAX_RECENT = 80

local recent = {}
local seen = {}
local replied = {}

local function notify(msg)
    print(PREFIX .. msg)
end

local function trackWhisper(name)
    if seen[name] then
        for i = 1, #recent do
            if recent[i] == name then
                table.remove(recent, i)
                break
            end
        end
    else
        seen[name] = true
    end
    recent[#recent + 1] = name
    while #recent > MAX_RECENT do
        seen[table.remove(recent, 1)] = nil
    end
end

local function replyRecent(input)
    if input == "reset" then
        wipe(replied)
        notify("Reply list cleared.")
        return
    end
    if #recent == 0 then
        notify("No players have whispered you yet.")
        return
    end
    local count, text = input:match("^(%d+)%s+(.+)$")
    if not text then
        text = input
        count = #recent
    else
        count = tonumber(count)
    end
    if not text or text == "" then
        notify("Usage: /rr MESSAGE or /rr N MESSAGE")
        return
    end
    local session = {}
    local start = math.max(#recent - count + 1, 1)
    for i = start, #recent do
        local name = recent[i]
        if name and not session[name] and not replied[name] then
            SendChatMessage(text, "WHISPER", nil, name)
            session[name] = true
            replied[name] = true
        end
    end
end

local listener = CreateFrame("Frame")
listener:RegisterEvent("CHAT_MSG_WHISPER")
listener:SetScript("OnEvent", function(_, _, _, sender)
    trackWhisper(sender)
end)

SLASH_REPLYRECENT1 = "/rr"
SlashCmdList["REPLYRECENT"] = replyRecent
