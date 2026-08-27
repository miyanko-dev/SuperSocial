local _, ns = ...

-- The server rate-limits whispers with a token bucket, observed live at ~10 messages of burst and a refill under 1/s (etrace: 10 accepted, then one yellow ERR_CHAT_THROTTLED per dropped message). The queue mirrors that bucket client-side: bursts up to BUCKET instantly, then sends each further whisper the moment a token matures, timer-scheduled, never polled. The refill rate is undocumented, so it calibrates itself AIMD-style: halved on a cap verdict, nudged up after clean oversized runs, persisted across sessions. Every delivered whisper is confirmed by its CHAT_MSG_WHISPER_INFORM echo, which is the only honest delivery ledger. If the cap trips anyway, the queue takes a CAP_PAUSE break and recovers with single probes.

local MAX_MESSAGE_LEN = 255 -- The server truncates beyond this and a truncated whisper never matches its echo.
local BUCKET = 8            -- Client-side burst budget, a safety margin under the observed ~10-message server bucket.
local RATE_DEFAULT = 0.8    -- Starting refill guess in whispers per second, just under the empirically derived ~1/s.
local RATE_FLOOR = 0.25     -- Never crawl slower than this.
local RATE_CEIL = 1.5       -- Never assume the server refills faster than this.
local RATE_STEP = 0.05      -- Additive increase after a clean run that actually exercised the bucket.
local CAP_PAUSE = 10        -- Hard break after a cap verdict before the next probe.
local MAX_TRIES = 3         -- Abandon a whisper swallowed on this many blast sends. Probe attempts against a closed cap never count.
local MAX_CAP_CYCLES = 18   -- Probe cycles before the run aborts (~3 minutes of the server refusing everything).
local OWNED_GRACE = 300     -- Remember what we sent someone this long, so a late echo can't be misread as a hand-typed answer.
local ECHO_TIMEOUT = 10     -- Seconds a send may sit unechoed outside a cap pause before it counts as swallowed, mirroring the probe grace.

local pending = {}      -- Queued, waiting for a token.
local unconfirmed = {}  -- Sent, no echo yet, in send order.
local ownedByShort = {} -- short name -> { at = last send, texts = every text sent }, to classify late echoes by exact text.
local collector         -- 0-delay timer so one command's loop queues fully before the burst.
local noticeTimer       -- 0-delay timer so mid-pause queuing announces once, not per recipient.
local capTimer          -- Running while the queue sits out the cap pause.
local pacer             -- Timer for the moment the next token matures.
local probing = false   -- A single probe is in flight; its verdict decides between resuming and pausing again.
local capCycles = 0     -- Probe cycles of the current cap episode, reset the moment the cap lifts.
local tokens = BUCKET   -- Client-side mirror of the server's bucket, full after login idle.
local lastRefill        -- GetTime of the last token refill.
local pacedNoticed = false  -- The current run has announced that it switched from burst to paced sending.
local queued = 0            -- Whispers accepted for this run, the Z of the Y/Z counter.
local bulkThisRun = false   -- This run carried at least one bulk whisper, so it earns a counter. A lone /wt is its own confirmation and gets none.
local progressText          -- Payload of the live counter line, so it can be found in chat and rewritten in place.
local cappedThisRun = false -- A cap verdict happened this run, so the rate must not grow from it.
local warnedText        -- Last over-long text warned about, so one bad blast warns once.
local sent = 0
local delivered = 0     -- Echo-confirmed whispers of the current run. Chat calls this "sent", because a server echo is what "sent" means from the player's side; the local keeps its name because `sent` above already counts attempts.
local purged = 0        -- Whispers dropped as unreachable this run, so they never read as failures.
local echoWatch         -- Timer sweeping unconfirmed for sends the server swallowed without any verdict.
local scheduleEchoSweep -- Forward declared: every send arms the sweep, which needs the run bookkeeping below.

-- Turn a %s format from GlobalStrings into a capture pattern.
local function toPattern(fmt)
    return "^" .. fmt:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1"):gsub("%%%%s", "(.+)") .. "$"
end

-- Server verdict wording. The client's own globals carry the exact (localized) text and are matched first; the literal enUS strings, verified against the 1.15.9 and 2.5.6 client data, back them up so a missing global can never blind the addon.
local THROTTLED_TEXT = ERR_CHAT_THROTTLED or "The number of messages that can be sent is limited, please wait to send another message."
local WRONG_FACTION_TEXT = ERR_CHAT_WRONG_FACTION or "You can only whisper to members of your alliance."
local NOT_FOUND_PATTERN = toPattern(ERR_CHAT_PLAYER_NOT_FOUND_S or "No player named '%s' is currently playing.")
local IGNORING_PATTERN = toPattern(ERR_IGNORING_YOU_S or "%s is ignoring you.")

-- Trial accounts draw their own rate-block wording instead of the throttle line; treat it as the same cap. The prefix match covers the store-link markup the full string carries.
local function isCapVerdict(msg)
    if msg == THROTTLED_TEXT then return true end
    if ERR_CHAT_RESTRICTED and msg == ERR_CHAT_RESTRICTED then return true end
    if ERR_CHAT_RESTRICTED_TRIAL and msg == ERR_CHAT_RESTRICTED_TRIAL then return true end
    return msg:find("^Free Trial accounts cannot send unlimited tells") ~= nil
end

-- The learned refill rate lives in the saved variables, so calibration survives reloads and sessions.
local function pacingRate()
    SuperSocialDB = SuperSocialDB or {}
    local rate = tonumber(SuperSocialDB.sendRate)
    if not rate or rate < RATE_FLOOR or rate > RATE_CEIL then rate = RATE_DEFAULT end
    return rate
end

local function setPacingRate(rate)
    SuperSocialDB = SuperSocialDB or {}
    SuperSocialDB.sendRate = math.max(RATE_FLOOR, math.min(RATE_CEIL, rate))
end

-- /ss reads and resets the learned rate through these, so a stale calibration is inspectable and curable in game.
function ns.PacingRate()
    return pacingRate()
end

function ns.ResetPacingRate()
    setPacingRate(RATE_DEFAULT)
    return RATE_DEFAULT
end

-- Rough send time for a run of `count` whispers: the burst goes instantly, the rest pace at the learned rate. Nil inside the burst or under 5s, because "~2s" is noise.
function ns.SendEta(count)
    local paced = count - BUCKET
    if paced <= 0 then return end
    local secs = paced / pacingRate()
    if secs < 5 then return end
    if secs >= 120 then return "~" .. math.ceil(secs / 60) .. " min" end
    return "~" .. math.ceil(secs) .. "s"
end

-- Quiet mode is on by default: a blast's own echo lines are noise, and the closing verdict is the honest record.
function ns.QuietBlasts()
    SuperSocialDB = SuperSocialDB or {}
    if SuperSocialDB.quietBlasts == nil then return true end
    return SuperSocialDB.quietBlasts
end

function ns.SetQuietBlasts(on)
    SuperSocialDB = SuperSocialDB or {}
    SuperSocialDB.quietBlasts = on and true or false
    return SuperSocialDB.quietBlasts
end

-- One chat line per run, rewritten where it stands as the count moves, so a quiet run still shows what it is doing. It stays a counter to the end: the closing verdict is appended as its own message instead, so the outcome is always the bottom line no matter what else printed during the run. The addon's own prefix and any chat timestamp sit ahead of the payload, so the payload is always the line's suffix. Rewriting is the only option here, because RemoveMessagesByPredicate strips a chat frame's hyperlinks along with the line.
local function writeProgress(text)
    local frame = DEFAULT_CHAT_FRAME
    local previous = progressText
    if previous and frame and frame.TransformMessages then
        local rewritten = false
        frame:TransformMessages(
            function(message) return message:sub(-#previous) == previous end,
            function(message, r, g, b, ...)
                rewritten = true
                return message:sub(1, #message - #previous) .. text, r, g, b, ...
            end)
        if rewritten then
            progressText = text
            return
        end
    end
    -- Nothing to rewrite: this is the run's first progress, or chat was cleared under it.
    progressText = text
    ns.Status(text)
end

-- Y/Z of whispers the server has confirmed. Unreachable targets ride along because they leave the run without ever reaching Y.
local function showProgress()
    if not bulkThisRun then return end
    local line = ns.Tint("sent", delivered .. "/" .. queued) .. " sent"
    if purged > 0 then
        line = line .. ", " .. ns.Tint("skip", purged .. " unreachable")
    end
    writeProgress(line .. ".")
end

local function refillTokens()
    local now = GetTime()
    tokens = math.min(BUCKET, tokens + (now - (lastRefill or now)) * pacingRate())
    lastRefill = now
end

local function sendOne(whisper, probeSend)
    if not probeSend then
        whisper.tries = whisper.tries + 1
    end
    if whisper.kind ~= "personal" then bulkThisRun = true end
    if not whisper.counted then
        whisper.counted = true
        sent = sent + 1
    end
    -- Record what we sent them, so even an echo arriving after we gave up is recognised as ours by its text.
    local short = ns.NameOnly(whisper.target)
    local owned = ownedByShort[short]
    if not owned then
        owned = { texts = {} }
        ownedByShort[short] = owned
    end
    owned.at = time()
    -- The kind rides along with the text: the chat filter mutes bulk sends and leaves conversation visible, and onEcho only needs the entry to exist.
    owned.texts[whisper.text] = whisper.kind or "blast"
    whisper.sentAt = GetTime()
    SendChatMessage(whisper.text, "WHISPER", nil, whisper.target)
    unconfirmed[#unconfirmed + 1] = whisper
    scheduleEchoSweep()
end

-- Send while tokens last, then wake up at the exact moment the next token matures. This is what keeps the queue at the server's maximum accepted rate without crossing it.
local function drainPaced()
    collector = nil
    pacer = nil
    refillTokens()
    while tokens >= 1 do
        local nextWhisper = table.remove(pending, 1)
        if not nextWhisper then break end
        tokens = tokens - 1
        sendOne(nextWhisper)
    end
    if #pending > 0 then
        local rate = pacingRate()
        if not pacedNoticed then
            pacedNoticed = true
            ns.Note(ns.Tint("cool", "Burst budget spent.") .. " Pacing the remaining " .. #pending .. " at " .. string.format("%.2f", rate) .. "/s so the server keeps accepting.")
        end
        -- Floor the delay so float dust just under a whole token can't arm a same-frame timer.
        pacer = C_Timer.NewTimer(math.max((1 - tokens) / rate, 0.05), drainPaced)
    end
end

-- Freeze the counter where the run stopped. Marking it also takes it out of matching range, so the next run's counter can't rewrite this one.
local function freezeProgress()
    if not progressText then return end
    writeProgress(progressText:gsub("%.$", "") .. ", " .. ns.Tint("skip", "stopped") .. ".")
    progressText = nil
end

local function cancelPause()
    if capTimer then capTimer:Cancel() end
    capTimer = nil
end

-- Zero the per-run bookkeeping, shared by the natural close and /ss stop.
local function resetRun()
    sent = 0
    delivered = 0
    purged = 0
    queued = 0
    bulkThisRun = false
    pacedNoticed = false
    cappedThisRun = false
end

-- Failed replies go back on the /rr list, so a swallowed reply is deferred, never lost.
local function giveUp(whisper)
    if whisper.kind == "reply" then
        ns.ReopenReply(whisper.target)
        ns.Fail("Couldn't send the reply to " .. whisper.target .. ".", "They're back on the /rr list.")
    else
        ns.Fail("Gave up on whispering " .. whisper.target, "after " .. MAX_TRIES .. " tries.")
    end
end

-- Close the run's books, a no-op while anything is still queued or in flight. The all-clear line is echo-counted: it only prints when every whisper of the run was confirmed delivered by the server. A clean run that exercised the bucket without a single cap verdict earns a small rate increase, the probing half of the calibration. Unreachable targets sit outside the failure math, so one offline player can't block that increase.
local function closeRun()
    if #pending > 0 or #unconfirmed > 0 then return end
    if sent > 0 then
        local failed = sent - delivered - purged
        local verdict
        if failed > 0 or purged > 0 then
            local bits = { ns.Tint("sent", delivered .. " sent") }
            if purged > 0 then bits[#bits + 1] = ns.Tint("skip", purged .. " unreachable") end
            if failed > 0 then bits[#bits + 1] = ns.Tint("skip", failed .. " failed") end
            verdict = table.concat(bits, ", ") .. " of " .. sent .. " " .. ns.Plural(sent, "whisper", "whispers") .. "."
        elseif sent > 1 then
            verdict = ns.Tint("sent", "Sent") .. " all " .. sent .. " whispers."
        elseif bulkThisRun then
            -- Every run closes with a verdict, however small, so the bottom line always says where it ended.
            verdict = ns.Tint("sent", "Sent") .. " 1 whisper."
        end
        -- A finished counter reads Y of Y, which a running one only reaches at its own end, so leaving it behind can never mislead a later run's rewrite.
        progressText = nil
        if verdict then
            -- The chat frame renders the final echo's own "To Name:" line after this handler returns; defer one frame so the verdict really is the last line in chat.
            C_Timer.After(0, function() ns.Note(verdict) end)
        end
        if failed == 0 and sent > BUCKET and not cappedThisRun then
            setPacingRate(pacingRate() + RATE_STEP)
        end
    end
    resetRun()
    -- Let go of long-idle recipients so a manual whisper much later reads as a personal answer again.
    local cutoff = time() - OWNED_GRACE
    for short, owned in pairs(ownedByShort) do
        if owned.at < cutoff then ownedByShort[short] = nil end
    end
end

-- Sweep for sends the server swallowed with no echo, no error and no cap verdict. Outside a pause each gets ECHO_TIMEOUT seconds, then recycles (or gives up past its try budget), so one lost echo can never wedge the run's books.
local function echoSweep()
    echoWatch = nil
    -- A pause owns its own recycling, and the probe that ends it re-arms the sweep.
    if capTimer or probing then return end
    local now = GetTime()
    for i = #unconfirmed, 1, -1 do
        local whisper = unconfirmed[i]
        if now - whisper.sentAt >= ECHO_TIMEOUT then
            table.remove(unconfirmed, i)
            if whisper.tries >= MAX_TRIES then
                giveUp(whisper)
            else
                table.insert(pending, 1, whisper)
            end
        end
    end
    scheduleEchoSweep()
    if #pending > 0 and not pacer and not collector then
        drainPaced()
    else
        closeRun()
    end
end

-- Arm the sweep for the oldest unechoed send. Idempotent, so every send can call it blindly.
function scheduleEchoSweep()
    if echoWatch or #unconfirmed == 0 then return end
    echoWatch = C_Timer.NewTimer(math.max(0.5, unconfirmed[1].sentAt + ECHO_TIMEOUT - GetTime()), echoSweep)
end

-- Forward declared: sendProbe arms a watchdog that fires probeAfterPause.
local probeAfterPause

-- Risk exactly one whisper against a cap of unknown state. Its echo releases the rest; its cap verdict starts the next pause. The watchdog guarantees a verdictless probe recycles instead of stalling the run silently.
local function sendProbe()
    cancelPause()
    local probe = table.remove(pending, 1)
    if not probe then
        probing = false
        closeRun()
        return
    end
    probe.probed = true
    probing = true
    refillTokens()
    tokens = math.max(0, tokens - 1)
    sendOne(probe, true)
    capTimer = C_Timer.NewTimer(CAP_PAUSE, probeAfterPause)
    ns.Note(ns.Tint("cool", "Probing with " .. probe.target) .. ", " .. #pending .. " waiting.")
end

-- The server refused every probe for MAX_CAP_CYCLES straight: stop, hand replies back to /rr and close the run.
local function abortEpisode()
    local lost = #unconfirmed + #pending
    for _, whisper in ipairs(unconfirmed) do
        if whisper.kind == "reply" then ns.ReopenReply(whisper.target) end
    end
    for _, whisper in ipairs(pending) do
        if whisper.kind == "reply" then ns.ReopenReply(whisper.target) end
    end
    wipe(unconfirmed)
    wipe(pending)
    probing = false
    cancelPause()
    capCycles = 0
    ns.Fail("Whisper cap never lifted.", lost .. " unsent after " .. math.floor(MAX_CAP_CYCLES * CAP_PAUSE / 60) .. " minutes. Replies went back to the /rr list.")
    closeRun()
end

-- Pause over: everything still unechoed was swallowed (it had CAP_PAUSE seconds to echo). Recycle it, rotating failed probes to the back, and probe again.
function probeAfterPause()
    capTimer = nil
    probing = false
    capCycles = capCycles + 1
    if capCycles > MAX_CAP_CYCLES then
        abortEpisode()
        return
    end
    for i = #unconfirmed, 1, -1 do
        local whisper = table.remove(unconfirmed, i)
        if whisper.tries >= MAX_TRIES then
            giveUp(whisper)
        elseif whisper.probed then
            whisper.probed = nil
            pending[#pending + 1] = whisper
        else
            table.insert(pending, 1, whisper)
        end
    end
    sendProbe()
end

local function onThrottled()
    -- Only sends of ours draw a cap verdict.
    if #unconfirmed == 0 then return end
    if probing then
        -- The probe's own verdict: still capped, replace its watchdog with a fresh pause.
        probing = false
        cancelPause()
        local waiting = #pending + #unconfirmed
        ns.Note(ns.Tint("skip", "Still capped.") .. " " .. waiting .. " waiting, pausing another " .. CAP_PAUSE .. "s.")
        capTimer = C_Timer.NewTimer(CAP_PAUSE, probeAfterPause)
        return
    end
    -- During a pause, verdicts of pre-pause sends are already covered by the next probe cycle.
    if capTimer then return end
    -- The model was too optimistic: the server's bucket is empty though ours wasn't. Drain ours, halve the learned rate and take the break.
    capCycles = 0
    cappedThisRun = true
    tokens = 0
    lastRefill = GetTime()
    setPacingRate(pacingRate() * 0.5)
    if pacer then pacer:Cancel() end
    pacer = nil
    ns.Note(ns.Tint("skip", "Whisper cap hit.") .. " " .. delivered .. " of " .. queued .. " sent so far, slowing to " .. string.format("%.2f", pacingRate()) .. "/s and pausing " .. CAP_PAUSE .. "s.")
    capTimer = C_Timer.NewTimer(CAP_PAUSE, probeAfterPause)
end

-- A permanent failure: this target never echoes, so drop them everywhere or they'd be retried until the try budget burns.
local function purgeTarget(name)
    local short = ns.NameOnly(name)
    local removed = 0
    for i = #unconfirmed, 1, -1 do
        if ns.NameOnly(unconfirmed[i].target) == short then
            table.remove(unconfirmed, i)
            removed = removed + 1
            purged = purged + 1
        end
    end
    for i = #pending, 1, -1 do
        if ns.NameOnly(pending[i].target) == short then
            -- Only counted sends offset the failure math; a never-sent removal was never in `sent`.
            if pending[i].counted then purged = purged + 1 end
            table.remove(pending, i)
            removed = removed + 1
        end
    end
    if removed > 0 then
        ns.Fail("Skipping " .. short .. ".", "Unreachable, removed from this run.")
        showProgress()
    end
    if #unconfirmed == 0 and #pending == 0 then
        cancelPause()
        probing = false
        closeRun()
    elseif probing and #unconfirmed == 0 then
        -- The probe itself was the unreachable one; its verdict said nothing about the cap, so probe again.
        sendProbe()
    end
end

-- Every outgoing whisper echoes here, ours and the player's own. Confirmation demands an exact text and target match: a whisper counts as delivered only against its own echo, so the all-clear can never fire off someone else's proof (like a manual whisper to the same person mid-run).
local function onEcho(text, target)
    local short = ns.NameOnly(target)
    local hit
    for i, whisper in ipairs(unconfirmed) do
        if whisper.text == text and ns.NameOnly(whisper.target) == short then
            hit = i
            break
        end
    end

    if not hit then
        -- No exact in-flight match, so this echo proves nothing about the run. Ours by recorded text means a late echo of one we already moved past; anything else is the player whispering by hand.
        local owned = ownedByShort[short]
        local ours = owned and owned.texts[text]
        ns.OnWhisperDelivered(target, not ours)
        return
    end

    local whisper = table.remove(unconfirmed, hit)
    delivered = delivered + 1
    ns.OnWhisperDelivered(target, whisper.kind == "personal")
    showProgress()

    if probing and #unconfirmed == 0 then
        probing = false
        cancelPause()
        capCycles = 0
        if #pending > 0 then
            ns.Ok("Cap lifted.", #pending .. " " .. ns.Plural(#pending, "whisper", "whispers") .. " to go.")
        end
    end

    if not capTimer and not probing and #pending > 0 and not pacer then
        drainPaced()
    else
        closeRun()
    end
end

-- Split a message on ";" into separate whispers, dropping empty parts.
function ns.SplitWhisper(text)
    local parts = {}
    for piece in (text or ""):gmatch("[^;]+") do
        local part = piece:gsub("^%s+", ""):gsub("%s+$", "")
        if part ~= "" then parts[#parts + 1] = part end
    end
    return parts
end

-- Queue a whisper; a ";" in the text queues each part as its own whisper. The 0-delay timer lets a caller loop queue its whole run before the burst fires next frame. `kind` is "personal" (/wt: counts as an answer), "reply" (/rr: reopens on failure) or nil for plain blasts. All kinds share the token pacing and wait out an active pause.
function ns.QueueWhisper(text, target, kind)
    for _, part in ipairs(ns.SplitWhisper(text)) do
        if #part > MAX_MESSAGE_LEN then
            if part ~= warnedText then
                warnedText = part
                ns.Fail("Whisper too long.", #part .. " characters, the limit is " .. MAX_MESSAGE_LEN .. ". Skipped.")
            end
        else
            pending[#pending + 1] = { text = part, target = target, kind = kind, tries = 0 }
            queued = queued + 1
        end
    end
    if capTimer or probing then
        -- Announce once per command, not once per recipient, hence the 0-delay aggregation.
        if not noticeTimer then
            noticeTimer = C_Timer.NewTimer(0, function()
                noticeTimer = nil
                ns.Note(ns.Tint("cool", "Cap active.") .. " " .. #pending .. " queued until the server accepts again.")
            end)
        end
    elseif not collector and not pacer then
        collector = C_Timer.NewTimer(0, drainPaced)
    end
end

-- Abort the current run. Returns how many already went out and how many were still waiting, so the caller can report what the stop actually caught.
function ns.CancelQueue()
    local doneSent = sent
    local cancelled = #pending
    wipe(pending)
    wipe(unconfirmed)
    if collector then collector:Cancel() end
    collector = nil
    if noticeTimer then noticeTimer:Cancel() end
    noticeTimer = nil
    if pacer then pacer:Cancel() end
    pacer = nil
    if echoWatch then echoWatch:Cancel() end
    echoWatch = nil
    cancelPause()
    probing = false
    capCycles = 0
    resetRun()
    freezeProgress()
    return doneSent, cancelled
end

-- Event wiring stays below the ns definitions, so a wiring failure can never strip the public API.
local systemWatch = CreateFrame("Frame")
systemWatch:RegisterEvent("CHAT_MSG_SYSTEM")
systemWatch:SetScript("OnEvent", function(_, _, msg)
    if isCapVerdict(msg) then
        onThrottled()
        return
    end
    if msg == WRONG_FACTION_TEXT then
        local whisper = unconfirmed[1]
        if whisper then purgeTarget(whisper.target) end
        return
    end
    local name = msg:match(NOT_FOUND_PATTERN) or msg:match(IGNORING_PATTERN)
    if name then purgeTarget(name) end
end)

local confirmWatch = CreateFrame("Frame")
confirmWatch:RegisterEvent("CHAT_MSG_WHISPER_INFORM")
confirmWatch:SetScript("OnEvent", function(_, _, text, target)
    onEcho(text, target)
end)

-- Hide the repeating yellow cap error while a run is active; the addon's own status lines cover it. The filter API lives in ChatFrameUtil on 1.15.9 and 2.5.6, with the old global as fallback for older clients.
local addFilter = ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter or ChatFrame_AddMessageEventFilter
if addFilter then
    addFilter("CHAT_MSG_SYSTEM", function(_, _, msg)
        if isCapVerdict(msg) and (capTimer or probing or #unconfirmed > 0) then return true end
    end)

    -- Mute a run's own "To Name:" echoes, so the replies they draw aren't buried under fifty lines of your own outgoing text. The Y/Z counter stands in for them. Every bulk command is hidden the same way, /rr included; only /wt is left, because a single hand-aimed whisper is its own confirmation and starts no run to count. The queue's delivery ledger is unaffected, because it counts echoes on its own event frame and message filters never reach that.
    addFilter("CHAT_MSG_WHISPER_INFORM", function(_, _, text, target)
        if not ns.QuietBlasts() then return end
        local owned = ownedByShort[ns.NameOnly(target)]
        local kind = owned and owned.texts[text]
        if kind == "blast" or kind == "reply" then return true end
    end)
end
