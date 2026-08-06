local _, ns = ...

local tint = ns.Tint
local status = ns.Status
local ok = ns.Ok
local fail = ns.Fail
local note = ns.Note
local plural = ns.Plural

-- /rr replies to everyone whispered via /ww who has whispered back and hasn't been answered yet. /ww recipients accumulate across blasts; the listener below marks their replies as pending and the queue reports every outgoing whisper via ns.OnWhisperDelivered. Personal answers — an /rr or a manual whisper — are sticky: further whispers from that person won't re-queue them. Only a fresh /ww that includes them starts a new exchange. Tracking is session-only.
local whisperedByShort = {}  -- short name -> the full "Name-Realm" we whispered
local pendingReplyAt = {}    -- short name -> time of their still-unanswered reply
local answeredByShort = {}   -- short name -> true once answered; a fresh /ww clears it

-- A reply the queue couldn't deliver goes back on the unanswered list, so the next /rr picks that person up again.
function ns.ReopenReply(fullName)
    local short = ns.NameOnly(fullName)
    if not (short and whisperedByShort[short]) then return end
    answeredByShort[short] = nil
    pendingReplyAt[short] = time()
end

-- The queue classifies every outgoing whisper and reports it here, so ownership is never inferred from a counter. A blast clears their pending reply; only a personal whisper answers them for good.
function ns.OnWhisperDelivered(fullName, personal)
    local short = ns.NameOnly(fullName)
    if not (short and whisperedByShort[short]) then return end
    pendingReplyAt[short] = nil
    if personal then answeredByShort[short] = true end
end

-- Called by /ww after a send: recipients accumulate across blasts. A fresh blast re-arms anyone /rr already answered — new solicitation, new exchange.
function ns.TrackWhispered(names)
    for _, fullName in ipairs(names) do
        local short = ns.NameOnly(fullName)
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
        ok("Reply tracking reset.", "Run /ww, then /rr replies to whoever whispers back.")
        return
    end

    local opts = ns.ParseFlags(input)
    if opts.limitError then
        fail("-limit needs a number.", "e.g. /rr -limit 5 invite incoming.")
        return
    end
    if opts.flagError then
        fail("Flags go before the message.", opts.flagError .. " would have been whispered as text. e.g. /rr -limit 5 invite incoming.")
        return
    end
    if opts.useCooldown then
        fail("-cd doesn't apply to /rr.", "Cooldowns only guard /ww and /ws.")
        return
    end
    if not opts.text or opts.text == "" then
        note("Usage: /rr MESSAGE — reply to everyone whispered via /ww who whispered back and hasn't been answered. e.g. /rr invite incoming!")
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

    local groupSet = ns.BuildGroupSet()
    local blocked = ns.LoadBlocked()

    local skippedGroup, skippedRecentGroup, skippedBlocked = 0, 0, 0
    local eligible = {}
    for short in pairs(pendingReplyAt) do
        if groupSet[short] then
            skippedGroup = skippedGroup + 1
        elseif ns.WasRecentlyGrouped(short) then
            skippedRecentGroup = skippedRecentGroup + 1
        elseif ns.IsBlocked(blocked, whisperedByShort[short]) then
            skippedBlocked = skippedBlocked + 1
        else
            eligible[#eligible + 1] = whisperedByShort[short]
        end
    end
    -- Newest reply first, so a -limit keeps the most recent repliers.
    table.sort(eligible, function(a, b)
        return pendingReplyAt[ns.NameOnly(a)] > pendingReplyAt[ns.NameOnly(b)]
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
        local why = ns.SkipBreakdown(skipCounts)
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
            local why = ns.SkipBreakdown(skipCounts)
            if why then line = line .. " (" .. why .. ")" end
        end
        return line
    end

    -- Summary first, so it leads the outgoing whisper lines.
    status(summarize(tint("sent", "Replying to " .. sendCount)) .. ".")
    for i = 1, sendCount do
        local fullName = eligible[i]
        ns.QueueWhisper(opts.text, fullName, "reply")

        -- Answered by /rr is sticky, so their follow-up whispers won't re-queue them. Clear pending eagerly too; a reply the queue fails to deliver reopens via ns.ReopenReply.
        local short = ns.NameOnly(fullName)
        answeredByShort[short] = true
        pendingReplyAt[short] = nil
    end
end

-- Incoming half of the tracking: a /ww recipient writing back becomes a pending reply. The outgoing half arrives via ns.OnWhisperDelivered, so only one place ever classifies a whisper.
local listener = CreateFrame("Frame")
listener:RegisterEvent("CHAT_MSG_WHISPER")
listener:SetScript("OnEvent", function(_, _, _, otherParty)
    local short = ns.NameOnly(otherParty)
    if not (short and whisperedByShort[short]) then return end
    -- Once answered, follow-up whispers don't re-queue them.
    if not answeredByShort[short] then
        pendingReplyAt[short] = time()
    end
end)

SLASH_REPLYRECENT1 = "/rr"
SlashCmdList["REPLYRECENT"] = replyRecent
