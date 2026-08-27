local _, ns = ...

local tint = ns.Tint
local ok = ns.Ok
local fail = ns.Fail
local note = ns.Note
local plural = ns.Plural

-- /rr replies to everyone whispered via /ww who has whispered back and hasn't been answered yet. /ww recipients accumulate across blasts; the listener below marks their replies as pending and the queue reports every outgoing whisper via ns.OnWhisperDelivered. Personal answers — an /rr or a manual whisper — are sticky: further whispers from that person won't re-queue them. Only a fresh /ww that includes them starts a new exchange.

-- Tracking lives in the saved variables, so a /reload mid-session can't drop the people still waiting on an answer. Entries age out after TRACK_MINUTES, because a reply is an LFM conversation: past that window it's stale and answering it would read as spam, not as a reply.
local TRACK_MINUTES = 15

local tracking

local function pruneTracking(db)
    local cutoff = time() - TRACK_MINUTES * 60
    for short, at in pairs(db.seen) do
        if at < cutoff then
            db.seen[short] = nil
            db.whispered[short] = nil
            db.pending[short] = nil
            db.answered[short] = nil
        end
    end
    -- A record a fresh blast keeps alive can still hold an old reply; the window applies to the reply itself, not just the record.
    for short, at in pairs(db.pending) do
        if at < cutoff then db.pending[short] = nil end
    end
end

local function loadTracking()
    if tracking then return tracking end
    SuperSocialDB = SuperSocialDB or {}
    local db = SuperSocialDB.replies or {}
    SuperSocialDB.replies = db
    db.whispered = db.whispered or {}  -- short name -> the full "Name-Realm" we whispered
    db.pending = db.pending or {}      -- short name -> time of their still-unanswered reply
    db.answered = db.answered or {}    -- short name -> true once answered; a fresh /ww clears it
    db.seen = db.seen or {}            -- short name -> last time we whispered them or they wrote back, the clock the age-out runs on
    pruneTracking(db)
    tracking = db
    return db
end

-- A reply the queue couldn't deliver goes back on the unanswered list, so the next /rr picks that person up again.
function ns.ReopenReply(fullName)
    local short = ns.NameOnly(fullName)
    if not short then return end
    local db = loadTracking()
    if not db.whispered[short] then return end
    db.answered[short] = nil
    db.pending[short] = time()
    db.seen[short] = time()
end

-- The queue classifies every outgoing whisper and reports it here, so ownership is never inferred from a counter. A blast clears their pending reply; only a personal whisper answers them for good.
function ns.OnWhisperDelivered(fullName, personal)
    local short = ns.NameOnly(fullName)
    if not short then return end
    local db = loadTracking()
    if not db.whispered[short] then return end
    db.pending[short] = nil
    if personal then db.answered[short] = true end
end

-- Called by /ww after a send: recipients accumulate across blasts. A fresh blast re-arms anyone /rr already answered — new solicitation, new exchange.
function ns.TrackWhispered(names)
    local db = loadTracking()
    local now = time()
    for _, fullName in ipairs(names) do
        local short = ns.NameOnly(fullName)
        db.whispered[short] = fullName
        db.answered[short] = nil
        db.seen[short] = now
    end
end

-- /rr with no message answers the question you would otherwise have to guess at: how many people are still waiting.
local function replyStatus(db)
    local tracked, waiting = 0, {}
    for _ in pairs(db.whispered) do tracked = tracked + 1 end
    for short in pairs(db.pending) do
        local fullName = db.whispered[short]
        if fullName then waiting[#waiting + 1] = fullName end
    end
    if tracked == 0 then
        note("Nothing tracked yet. Run /ww, then /rr replies to whoever whispers back. e.g. /rr invite incoming!")
        return
    end
    local pending = #waiting
    if pending == 0 then
        note("No unanswered replies from " .. tracked .. " tracked. /rr MESSAGE answers them as they come in.")
        return
    end
    local line = tint("sent", pending .. " unanswered " .. plural(pending, "reply", "replies")) .. " from " .. tracked .. " tracked."
    -- Past a handful the names stop being scannable and the count is the useful part.
    if pending <= 10 then
        table.sort(waiting)
        line = line .. " Waiting: " .. table.concat(waiting, ", ") .. "."
    end
    note(line .. " /rr MESSAGE answers them all.")
end

local function replyRecent(input)
    input = (input or ""):gsub("^%s+", ""):gsub("%s+$", "")

    local db = loadTracking()
    pruneTracking(db)

    local command = input:lower()
    if command == "reset" or command == "clear" then
        wipe(db.whispered)
        wipe(db.pending)
        wipe(db.answered)
        wipe(db.seen)
        ok("Reply tracking reset.", "Run /ww, then /rr replies to whoever whispers back.")
        return
    end

    local opts = ns.ParseFlags(input)
    if ns.FlagMistake(opts, "/rr -limit 5 invite incoming") then return end
    if opts.who or opts.whoError then
        fail("-who doesn't apply to /rr.", "It replies to people who already whispered you, no /who involved.")
        return
    end
    if opts.useCooldown then
        fail("-cd doesn't apply to /rr.", "Cooldowns only guard /ww and /ws.")
        return
    end
    if not opts.text or opts.text == "" then
        replyStatus(db)
        return
    end

    local trackedCount = 0
    for _ in pairs(db.whispered) do trackedCount = trackedCount + 1 end
    if trackedCount == 0 then
        fail("No /ww whispers yet.", "Run /ww first, then /rr replies to whoever whispers back.")
        return
    end

    local pending = 0
    for _ in pairs(db.pending) do pending = pending + 1 end
    if pending == 0 then
        fail("No unanswered replies", "from your /ww whispers (" .. trackedCount .. " tracked).")
        return
    end

    local groupSet = ns.BuildGroupSet()
    local blocked = ns.LoadBlocked()

    local skippedGroup, skippedRecentGroup, skippedBlocked = 0, 0, 0
    local eligible = {}
    for short in pairs(db.pending) do
        if groupSet[short] then
            skippedGroup = skippedGroup + 1
        elseif ns.WasRecentlyGrouped(short) then
            skippedRecentGroup = skippedRecentGroup + 1
        elseif ns.IsBlocked(blocked, db.whispered[short]) then
            skippedBlocked = skippedBlocked + 1
        else
            eligible[#eligible + 1] = db.whispered[short]
        end
    end
    -- Newest reply first, so a -limit keeps the most recent repliers.
    table.sort(eligible, function(a, b)
        return db.pending[ns.NameOnly(a)] > db.pending[ns.NameOnly(b)]
    end)

    local sendCount = opts.limit and math.min(opts.limit, #eligible) or #eligible

    -- Counts behind the "N skipped" total, in the order the breakdown reads.
    local skipCounts = {
        blocked = skippedBlocked,
        group = skippedGroup,
        recentGroup = skippedRecentGroup,
        limit = #eligible - sendCount,
    }

    local pool = pending .. " unanswered " .. plural(pending, "reply", "replies")

    if sendCount == 0 then
        fail("Nobody to reply to.", "None of " .. pool .. " are eligible.")
        ns.SkipLine(skipCounts, pending)
        return
    end

    -- Same shape as a /ww run: who hears it, who doesn't, then the message.
    local eta = ns.SendEta(sendCount * #ns.SplitWhisper(opts.text))
    ok("Replying to", (sendCount == pending and "all " or sendCount .. " of ") .. pool .. (eta and (", " .. eta) or "") .. ".")
    ns.SkipLine(skipCounts, pending - sendCount)
    ns.QuoteMessage(opts.text)
    for i = 1, sendCount do
        local fullName = eligible[i]
        ns.QueueWhisper(opts.text, fullName, "reply")

        -- Answered by /rr is sticky, so their follow-up whispers won't re-queue them. Clear pending eagerly too; a reply the queue fails to deliver reopens via ns.ReopenReply.
        local short = ns.NameOnly(fullName)
        db.answered[short] = true
        db.pending[short] = nil
    end
end

-- Incoming half of the tracking: a /ww recipient writing back becomes a pending reply. The outgoing half arrives via ns.OnWhisperDelivered, so only one place ever classifies a whisper.
local listener = CreateFrame("Frame")
listener:RegisterEvent("CHAT_MSG_WHISPER")
listener:SetScript("OnEvent", function(_, _, _, otherParty)
    local short = ns.NameOnly(otherParty)
    if not short then return end
    local db = loadTracking()
    if not db.whispered[short] then return end
    -- Once answered, follow-up whispers don't re-queue them.
    if not db.answered[short] then
        db.pending[short] = time()
    end
    -- An active conversation keeps itself alive past the age-out.
    db.seen[short] = time()
end)

SLASH_REPLYRECENT1 = "/rr"
SlashCmdList["REPLYRECENT"] = replyRecent
