local _, ns = ...

local WHISPER_WINDOW = 15 * 60   -- reply only to whispers from the last 15 minutes
local REPLY_COOLDOWN = 30 * 60   -- don't re-reply to the same person within 30 minutes

local tint = ns.tint
local status = ns.status
local detail = ns.detail
local plural = ns.plural

-- name -> timestamp of their most recent whisper / our most recent /rr reply.
local whisperedAt = {}
local repliedAt = {}

local function trackWhisper(name)
    whisperedAt[name] = time()
end

local function parseReplyInput(input)
    local tokens = {}
    for token in input:gmatch("%S+") do
        tokens[#tokens + 1] = token
    end

    local cursor = 1
    local limit
    local excludes = {}
    local preview = false

    while tokens[cursor] and tokens[cursor]:sub(1, 1) == "-" and #tokens[cursor] > 1 do
        local val = tokens[cursor]:sub(2)
        if val == "p" then
            preview = true
        elseif val:match("^%d+$") then
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
    return limit, excludes, table.concat(words, " "), preview
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
        -- Drop the whisper history so only whispers received after this point
        -- are eligible to reply to. Not persisted: a reload or re-login resets
        -- it too, since the history is read live from chat.
        wipe(whisperedAt)
        wipe(repliedAt)
        status("Reply tracking reset — only new whispers will be replied to.")
        return
    end

    local now = time()

    -- Age out whispers past the 15-minute window and replies past the
    -- 30-minute cooldown, so the tables stay bounded over a long session.
    for name, ts in pairs(whisperedAt) do
        if ts < now - WHISPER_WINDOW then whisperedAt[name] = nil end
    end
    for name, ts in pairs(repliedAt) do
        if ts < now - REPLY_COOLDOWN then repliedAt[name] = nil end
    end

    local recentCount = 0
    for _ in pairs(whisperedAt) do recentCount = recentCount + 1 end
    if recentCount == 0 then
        status(tint("skip", "No recent whisperers") .. " to reply to.")
        return
    end

    local limit, excludes, text, preview = parseReplyInput(input)
    if not text or text == "" then return end

    -- Eligible = whispered within the window, not excluded, not still on reply
    -- cooldown. Sorted newest-first so a -N limit keeps the most recent.
    local eligible = {}
    for name in pairs(whisperedAt) do
        if not matchesExcludes(name, excludes) and not repliedAt[name] then
            eligible[#eligible + 1] = name
        end
    end
    table.sort(eligible, function(a, b) return whisperedAt[a] > whisperedAt[b] end)

    local sendCount = limit and math.min(limit, #eligible) or #eligible
    if sendCount == 0 then
        status(tint("skip", "Nobody to reply to") .. " — 0 of " .. recentCount .. " recent eligible.")
        return
    end

    local skipped = recentCount - sendCount

    if preview then
        local line = tint("muted", "Preview") .. " — would reply to " .. sendCount .. " of " .. recentCount .. " recent " .. plural(recentCount, "whisperer", "whisperers")
        if skipped > 0 then
            line = line .. ", " .. tint("skip", skipped .. " skipped")
        end
        status(line .. ".")
        detail(tint("muted", "Message:") .. " " .. text)
        return
    end

    for i = 1, sendCount do
        local fullName = eligible[i]
        ns.queueWhisper(text, fullName, "reply", "replies")
        repliedAt[fullName] = now
    end

    local line = tint("sent", "Replying to " .. sendCount) .. " of " .. recentCount .. " recent " .. plural(recentCount, "whisperer", "whisperers")
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
