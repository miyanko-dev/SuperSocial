local _, ns = ...

local tint = ns.tint
local status = ns.status
local plural = ns.plural

-- /rr replies to the people from your most recent /ww blast who have whispered
-- you back. /ww records the batch; the listener below marks which of them
-- replied. The batch is session-only and replaced on every /ww, so /rr always
-- targets the latest blast — never random whisperers or an earlier batch.
local batchByShort = {}    -- short name -> the full "Name-Realm" we whispered
local batchRepliedAt = {}  -- short name -> time that batch member whispered back

-- Called by /ww after a send: these names become the new batch, clearing the
-- previous one and any replies it had collected.
function ns.beginReplyBatch(names)
    wipe(batchByShort)
    wipe(batchRepliedAt)
    for _, fullName in ipairs(names) do
        batchByShort[ns.nameOnly(fullName)] = fullName
    end
end

local function replyRecent(input)
    input = (input or ""):gsub("^%s+", ""):gsub("%s+$", "")

    local command = input:lower()
    if command == "reset" or command == "clear" then
        wipe(batchByShort)
        wipe(batchRepliedAt)
        status("Reply tracking reset. Run /ww, then /rr replies to whoever whispers back.")
        return
    end

    local opts = ns.parseFlags(input)
    if not opts.text or opts.text == "" then
        status(tint("muted", "Usage:") .. " /rr MESSAGE — reply to everyone from your last /ww who whispered back. "
            .. tint("muted", "e.g.") .. " " .. tint("cool", "/rr invite incoming!") .. ".")
        return
    end

    local batchSize = 0
    for _ in pairs(batchByShort) do batchSize = batchSize + 1 end
    if batchSize == 0 then
        status(tint("skip", "No /ww batch yet.") .. " Run /ww first, then /rr replies to whoever whispers back.")
        return
    end

    local replied = 0
    for _ in pairs(batchRepliedAt) do replied = replied + 1 end
    if replied == 0 then
        status(tint("skip", "No replies yet") .. " from your last /ww batch (" .. batchSize .. " whispered).")
        return
    end

    local groupSet = ns.buildGroupSet()
    local skip = opts.useSkip and ns.loadSkip() or nil
    local cooldownBucket
    local cooldownMinutes
    if opts.useCooldown then
        cooldownBucket = ns.loadCooldowns()
        if opts.cooldownSeconds then
            ns.pruneCooldowns(cooldownBucket, opts.cooldownSeconds)
            cooldownMinutes = math.floor(opts.cooldownSeconds / 60)
        end
    end

    local skippedGroup, skippedSkip, skippedCool = 0, 0, 0
    local eligible = {}
    for short in pairs(batchRepliedAt) do
        local fullName = batchByShort[short]
        if groupSet[short] then
            skippedGroup = skippedGroup + 1
        elseif skip and skip[fullName] then
            skippedSkip = skippedSkip + 1
        elseif cooldownBucket and not ns.isCool(cooldownBucket, fullName, opts.cooldownSeconds) then
            skippedCool = skippedCool + 1
        else
            eligible[#eligible + 1] = fullName
        end
    end
    -- Newest reply first, so a -N limit keeps the most recent repliers.
    table.sort(eligible, function(a, b)
        return batchRepliedAt[ns.nameOnly(a)] > batchRepliedAt[ns.nameOnly(b)]
    end)

    local sendCount = opts.limit and math.min(opts.limit, #eligible) or #eligible

    -- Counts behind the "N skipped" total, in the order the breakdown reads.
    local skipCounts = {
        skiplist = skippedSkip,
        cooldown = skippedCool,
        group = skippedGroup,
        limit = #eligible - sendCount,
    }

    if sendCount == 0 then
        local line = tint("skip", "Nobody to reply to.") .. " None of " .. replied .. " who replied are eligible"
        local why = ns.skipBreakdown(skipCounts)
        if why then line = line .. " (" .. why .. ")" end
        status(line .. ".")
        return
    end

    local skipped = replied - sendCount

    -- Fold the count, skip breakdown, and what the reply records into one line.
    local function summarize(lead, isPreview)
        local line = lead .. " of " .. replied .. " who replied"
        if skipped > 0 then
            line = line .. ", " .. tint("skip", skipped .. " skipped")
            local why = ns.skipBreakdown(skipCounts)
            if why then line = line .. " (" .. why .. ")" end
        end
        local applied = ns.appliedSummary(sendCount, skip ~= nil, cooldownMinutes, isPreview)
        if applied then line = line .. ", " .. applied end
        return line
    end

    if opts.preview then
        status(summarize(tint("muted", "Preview.") .. " I'd reply to " .. sendCount, true)
            .. ". " .. tint("muted", "Message:") .. " " .. opts.text)
        return
    end

    -- Summary first, so it leads the outgoing whisper lines.
    status(summarize(tint("sent", "Replying to " .. sendCount), false) .. ".")
    for i = 1, sendCount do
        local fullName = eligible[i]
        ns.queueWhisper(opts.text, fullName)
        if skip then skip[fullName] = true end
        -- Only a timed -cd records new recipients; bare -cd just reads the pool.
        if cooldownBucket and cooldownMinutes then cooldownBucket[fullName] = time() end
    end
end

-- Mark a reply only when it comes from someone in the current /ww batch.
local listener = CreateFrame("Frame")
listener:RegisterEvent("CHAT_MSG_WHISPER")
listener:SetScript("OnEvent", function(_, _, _, sender)
    local short = ns.nameOnly(sender)
    if short and batchByShort[short] then
        batchRepliedAt[short] = time()
    end
end)

SLASH_REPLYRECENT1 = "/rr"
SlashCmdList["REPLYRECENT"] = replyRecent
