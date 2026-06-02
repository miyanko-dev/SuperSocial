local _, ns = ...

local MAX_RECENT = 80

local tint = ns.tint
local status = ns.status
local plural = ns.plural

local recent = {}
local seen = {}
local replied = {}

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

    local command = input:lower()
    if command == "reset" or command == "clear" then
        -- Drop the recent-whisperer history so only whispers received after
        -- this point are eligible to reply to. Not persisted: a reload or
        -- re-login resets it too, since the history is read live from chat.
        wipe(recent)
        wipe(seen)
        wipe(replied)
        status("Reply tracking reset — only new whispers will be replied to.")
        return
    end
    if #recent == 0 then
        status(tint("skip", "No recent whisperers") .. " to reply to.")
        return
    end

    local limit, excludes, text = parseReplyInput(input)
    if not text or text == "" then return end
    limit = limit or #recent

    -- Walk newest-first so a limit keeps the most recent whisperers.
    local eligible = {}
    for i = #recent, 1, -1 do
        local name = recent[i]
        if name and not matchesExcludes(name, excludes) and not replied[name] then
            eligible[#eligible + 1] = name
        end
    end

    local sendCount = math.min(limit, #eligible)
    if sendCount == 0 then
        status(tint("skip", "Nobody to reply to") .. " — 0 of " .. #recent .. " recent eligible.")
        return
    end

    for i = 1, sendCount do
        local fullName = eligible[i]
        ns.queueWhisper(text, fullName)
        replied[fullName] = true
    end

    local line = tint("sent", "Replying to " .. sendCount) .. " of " .. #recent .. " recent " .. plural(#recent, "whisperer", "whisperers")
    local skipped = #recent - sendCount
    if skipped > 0 then
        line = line .. ", " .. tint("skip", skipped .. " skipped")
    end
    status(line .. ".")
end

local listener = CreateFrame("Frame")
listener:RegisterEvent("CHAT_MSG_WHISPER")
listener:SetScript("OnEvent", function(_, _, _, sender)
    trackWhisper(sender)
end)

SLASH_REPLYRECENT1 = "/rr"
SlashCmdList["REPLYRECENT"] = replyRecent
