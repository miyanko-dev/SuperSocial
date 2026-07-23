local _, ns = ...

local tint = ns.tint
local status = ns.status
local ok = ns.ok
local fail = ns.fail
local info = ns.info
local plural = ns.plural

-- /rr replies to everyone whispered via /ww who has whispered back and hasn't
-- been answered yet. /ww recipients accumulate across blasts; the listener
-- below marks their replies as pending and clears them again on any outgoing
-- whisper. Personal answers — an /rr or a manual whisper — are sticky: further
-- whispers from that person won't re-queue them. Only a fresh /ww that
-- includes them starts a new exchange. Tracking is session-only.
local whisperedByShort = {}  -- short name -> the full "Name-Realm" we whispered
local pendingReplyAt = {}    -- short name -> time of their still-unanswered reply
local answeredByShort = {}   -- short name -> true once answered; a fresh /ww clears it

-- Whispers the queue sends are blasts, not personal answers: the listener
-- clears pending for them without turning sticky. Counted per name because
-- back-to-back runs can queue the same person twice.
local blastOutgoing = {}

function ns.markBlastWhisper(fullName)
    local short = ns.nameOnly(fullName)
    if not short then return end
    blastOutgoing[short] = (blastOutgoing[short] or 0) + 1
end

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
        wipe(blastOutgoing)
        ok("Reply tracking reset.", "Run /ww, then /rr replies to whoever whispers back.")
        return
    end

    local opts = ns.parseFlags(input)
    if opts.limitError then
        fail("-limit needs a number.", "e.g. /rr -limit 5 invite incoming.")
        return
    end
    if opts.useCooldown then
        fail("-cd doesn't apply to /rr.", "Cooldowns only guard /ww and /ws.")
        return
    end
    if not opts.text or opts.text == "" then
        info("Usage: /rr MESSAGE — reply to everyone whispered via /ww who whispered back and hasn't been answered. e.g. /rr invite incoming!")
        return
    end

    local trackedCount = 0
    for _ in pairs(whisperedByShort) do trackedCount = trackedCount + 1 end
    if trackedCount == 0 then
        fail("No /ww whispers yet.", "Run /ww first, then /rr replies to whoever whispers back.")
        return
    end

    local pending = 0
    for _ in pairs(pendingReplyAt) do pending = pending + 1 end
    if pending == 0 then
        fail("No unanswered replies", "from your /ww whispers (" .. trackedCount .. " tracked).")
        return
    end

    local groupSet = ns.buildGroupSet()
    local blocked = ns.loadBlocked()

    local skippedGroup, skippedRecentGroup, skippedBlocked = 0, 0, 0
    local eligible = {}
    for short in pairs(pendingReplyAt) do
        if groupSet[short] then
            skippedGroup = skippedGroup + 1
        elseif ns.wasRecentlyGrouped(short) then
            skippedRecentGroup = skippedRecentGroup + 1
        elseif ns.isBlocked(blocked, whisperedByShort[short]) then
            skippedBlocked = skippedBlocked + 1
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
        blocked = skippedBlocked,
        group = skippedGroup,
        recentGroup = skippedRecentGroup,
        limit = #eligible - sendCount,
    }

    if sendCount == 0 then
        local detail = "None of " .. pending .. " unanswered " .. plural(pending, "reply", "replies") .. " are eligible"
        local why = ns.skipBreakdown(skipCounts)
        if why then detail = detail .. " (" .. why .. ")" end
        fail("Nobody to reply to.", detail .. ".")
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
-- pending reply, any outgoing whisper to them clears it. Queued blasts stop
-- there; a manual whisper also answers them for good, like an /rr reply.
local listener = CreateFrame("Frame")
listener:RegisterEvent("CHAT_MSG_WHISPER")
listener:RegisterEvent("CHAT_MSG_WHISPER_INFORM")
listener:SetScript("OnEvent", function(_, event, _, otherParty)
    local short = ns.nameOnly(otherParty)
    if not (short and whisperedByShort[short]) then return end
    if event == "CHAT_MSG_WHISPER" then
        -- Once answered, follow-up whispers don't re-queue them.
        if not answeredByShort[short] then
            pendingReplyAt[short] = time()
        end
    else
        pendingReplyAt[short] = nil
        local blasts = blastOutgoing[short]
        if blasts then
            blastOutgoing[short] = blasts > 1 and blasts - 1 or nil
        else
            answeredByShort[short] = true
        end
    end
end)

SLASH_REPLYRECENT1 = "/rr"
SlashCmdList["REPLYRECENT"] = replyRecent
