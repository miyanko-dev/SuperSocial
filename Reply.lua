local _, ns = ...

local tint = ns.tint
local status = ns.status
local plural = ns.plural

-- /rr replies to everyone whispered via /ww who has whispered back and hasn't
-- been answered yet. /ww recipients accumulate across blasts; the listener
-- below marks their replies as pending and clears them again on any outgoing
-- whisper — an /rr, a manual reply, or the next /ww blast. People /rr has
-- answered stay answered even if they whisper again; only a fresh /ww that
-- includes them starts a new exchange. Tracking is session-only.
local whisperedByShort = {}  -- short name -> the full "Name-Realm" we whispered
local pendingReplyAt = {}    -- short name -> time of their still-unanswered reply
local answeredByShort = {}   -- short name -> true once /rr replied; a fresh /ww clears it

-- Called by /ww after a send: recipients accumulate across blasts. A fresh
-- blast re-arms anyone /rr already answered — new solicitation, new exchange.
function ns.trackWhispered(names)
    for _, fullName in ipairs(names) do
        local short = ns.nameOnly(fullName)
        whisperedByShort[short] = fullName
        answeredByShort[short] = nil
    end
end

local function replyRecent(input)
    input = (input or ""):gsub("^%s+", ""):gsub("%s+$", "")

    local command = input:lower()
    if command == "reset" or command == "clear" then
        wipe(whisperedByShort)
        wipe(pendingReplyAt)
        wipe(answeredByShort)
        status("Reply tracking reset. Run /ww, then /rr replies to whoever whispers back.")
        return
    end

    local opts = ns.parseFlags(input)
    if opts.limitError then
        status(tint("skip", "-limit needs a number.") .. " " .. tint("muted", "e.g.") .. " " .. tint("cool", "/rr -limit 5 invite incoming") .. ".")
        return
    end
    if opts.useCooldown then
        status(tint("skip", "-cd doesn't apply to /rr.") .. " Cooldowns only guard /ww and /ws.")
        return
    end
    if not opts.text or opts.text == "" then
        status(tint("muted", "Usage:") .. " /rr MESSAGE — reply to everyone whispered via /ww who whispered back and hasn't been answered. "
            .. tint("muted", "e.g.") .. " " .. tint("cool", "/rr invite incoming!") .. ".")
        return
    end

    local trackedCount = 0
    for _ in pairs(whisperedByShort) do trackedCount = trackedCount + 1 end
    if trackedCount == 0 then
        status(tint("skip", "No /ww whispers yet.") .. " Run /ww first, then /rr replies to whoever whispers back.")
        return
    end

    local pending = 0
    for _ in pairs(pendingReplyAt) do pending = pending + 1 end
    if pending == 0 then
        status(tint("skip", "No unanswered replies") .. " from your /ww whispers (" .. trackedCount .. " tracked).")
        return
    end

    local groupSet = ns.buildGroupSet()

    local skippedGroup = 0
    local eligible = {}
    for short in pairs(pendingReplyAt) do
        if groupSet[short] then
            skippedGroup = skippedGroup + 1
        else
            eligible[#eligible + 1] = whisperedByShort[short]
        end
    end
    -- Newest reply first, so a -limit keeps the most recent repliers.
    table.sort(eligible, function(a, b)
        return pendingReplyAt[ns.nameOnly(a)] > pendingReplyAt[ns.nameOnly(b)]
    end)

    local sendCount = opts.limit and math.min(opts.limit, #eligible) or #eligible

    -- Counts behind the "N skipped" total, in the order the breakdown reads.
    local skipCounts = {
        group = skippedGroup,
        limit = #eligible - sendCount,
    }

    if sendCount == 0 then
        local line = tint("skip", "Nobody to reply to.") .. " None of " .. pending .. " unanswered " .. plural(pending, "reply", "replies") .. " are eligible"
        local why = ns.skipBreakdown(skipCounts)
        if why then line = line .. " (" .. why .. ")" end
        status(line .. ".")
        return
    end

    local skipped = pending - sendCount

    -- Fold the count and skip breakdown into one status line.
    local function summarize(lead)
        local line = lead .. " of " .. pending .. " unanswered " .. plural(pending, "reply", "replies")
        if skipped > 0 then
            line = line .. ", " .. tint("skip", skipped .. " skipped")
            local why = ns.skipBreakdown(skipCounts)
            if why then line = line .. " (" .. why .. ")" end
        end
        return line
    end

    -- Summary first, so it leads the outgoing whisper lines.
    status(summarize(tint("sent", "Replying to " .. sendCount)) .. ".")
    for i = 1, sendCount do
        local fullName = eligible[i]
        ns.queueWhisper(opts.text, fullName)

        -- Answered by /rr is sticky, so their follow-up whispers won't
        -- re-queue them. Clear pending eagerly too: the INFORM event also
        -- does it, but the queue trickles.
        local short = ns.nameOnly(fullName)
        answeredByShort[short] = true
        pendingReplyAt[short] = nil
    end
end

-- Track both directions for /ww recipients: an incoming whisper marks a
-- pending reply, any outgoing whisper to them counts as answered — whether
-- from /rr, a manual reply, or the next /ww blast.
local listener = CreateFrame("Frame")
listener:RegisterEvent("CHAT_MSG_WHISPER")
listener:RegisterEvent("CHAT_MSG_WHISPER_INFORM")
listener:SetScript("OnEvent", function(_, event, _, otherParty)
    local short = ns.nameOnly(otherParty)
    if not (short and whisperedByShort[short]) then return end
    if event == "CHAT_MSG_WHISPER" then
        -- Once /rr answered them, follow-up whispers don't re-queue them.
        if not answeredByShort[short] then
            pendingReplyAt[short] = time()
        end
    else
        pendingReplyAt[short] = nil
    end
end)

SLASH_REPLYRECENT1 = "/rr"
SlashCmdList["REPLYRECENT"] = replyRecent
