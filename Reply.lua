local PREFIX = "|cffffff00[Whisper Them All!]:|r "
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

local function parseReplyInput(input)
    local tokens = {}
    for token in input:gmatch("%S+") do
        tokens[#tokens + 1] = token
    end

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
    for i = cursor, #tokens do
        words[#words + 1] = tokens[i]
    end
    return limit, excludes, table.concat(words, " ")
end

local function matchesExcludes(name, excludes)
    if #excludes == 0 then return false end
    local lower = name:lower()
    local short = lower:match("^([^-]+)") or lower
    for _, filter in ipairs(excludes) do
        if short:find(filter, 1, true) then return true end
    end
    return false
end

local function replyRecent(input)
    input = (input or ""):gsub("^%s+", ""):gsub("%s+$", "")

    if input:lower() == "reset" then
        wipe(replied)
        notify("Reply list cleared.")
        return
    end
    if #recent == 0 then
        notify("No players have whispered you yet.")
        return
    end

    local limit, excludes, text = parseReplyInput(input)
    if not text or text == "" then
        notify("Usage: /rr MESSAGE or /rr -N MESSAGE")
        return
    end
    limit = limit or #recent

    local session = {}
    local sent = 0
    for i = #recent, 1, -1 do
        if sent >= limit then break end
        local name = recent[i]
        if name and not session[name] and not replied[name]
            and not matchesExcludes(name, excludes) then
            SendChatMessage(text, "WHISPER", nil, name)
            session[name] = true
            replied[name] = true
            sent = sent + 1
        end
    end
    if sent > 0 and WhisperThemAll and WhisperThemAll.Announce then
        WhisperThemAll.Announce(sent)
    end
end

local listener = CreateFrame("Frame")
listener:RegisterEvent("CHAT_MSG_WHISPER")
listener:SetScript("OnEvent", function(_, _, _, sender)
    trackWhisper(sender)
end)

SLASH_REPLYRECENT1 = "/rr"
SlashCmdList["REPLYRECENT"] = replyRecent
