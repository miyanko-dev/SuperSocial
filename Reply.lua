local _, ns = ...

local tint = ns.tint
local status = ns.status
local plural = ns.plural

-- Everyone who has whispered us this session, name -> most recent timestamp.
-- This is the /rr recipient pool. It isn't persisted: a reload, relog, or
-- "/rr reset" clears it. Replying skips nobody by default — only -skip and -cd
-- filter, exactly as on /ww.
local whisperedAt = {}

local function trackWhisper(name)
    whisperedAt[name] = time()
end

local function replyRecent(input)
    input = (input or ""):gsub("^%s+", ""):gsub("%s+$", "")

    local command = input:lower()
    if command == "reset" or command == "clear" then
        wipe(whisperedAt)
        status("Reply tracking reset — only people who whisper you from now on will be replied to.")
        return
    end

    local opts = ns.parseFlags(input)
    if not opts.text or opts.text == "" then return end

    local total = 0
    for _ in pairs(whisperedAt) do total = total + 1 end
    if total == 0 then
        status(tint("skip", "No whisperers") .. " to reply to.")
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

    -- Sorted newest-first so a -N limit keeps the most recent whisperers.
    local skippedGroup, skippedSkip, skippedCool = 0, 0, 0
    local eligible = {}
    for name in pairs(whisperedAt) do
        if groupSet[ns.nameOnly(name)] then
            skippedGroup = skippedGroup + 1
        elseif skip and skip[name] then
            skippedSkip = skippedSkip + 1
        elseif cooldownBucket and not ns.isCool(cooldownBucket, name, opts.cooldownSeconds) then
            skippedCool = skippedCool + 1
        else
            eligible[#eligible + 1] = name
        end
    end
    table.sort(eligible, function(a, b) return whisperedAt[a] > whisperedAt[b] end)

    local sendCount = opts.limit and math.min(opts.limit, #eligible) or #eligible

    -- Counts behind the "N skipped" total, in the order the breakdown reads.
    local skipCounts = {
        skiplist = skippedSkip,
        cooldown = skippedCool,
        group = skippedGroup,
        limit = #eligible - sendCount,
    }

    if sendCount == 0 then
        local line = tint("skip", "Nobody to reply to") .. " — 0 of " .. total .. " eligible"
        local why = ns.skipBreakdown(skipCounts)
        if why then line = line .. " (" .. why .. ")" end
        status(line .. ".")
        return
    end

    local skipped = total - sendCount

    -- Fold the count, skip breakdown, and list changes into one status line.
    local function summarize(lead, isPreview)
        local line = lead .. " of " .. total .. " " .. plural(total, "whisperer", "whisperers")
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
        status(summarize(tint("muted", "Preview") .. " — would reply to " .. sendCount, true)
            .. ". " .. tint("muted", "Message:") .. " " .. opts.text)
        return
    end

    -- Summary first, so "starting whispers" leads the outgoing whisper lines.
    status(summarize(tint("sent", "Replying to " .. sendCount), false) .. " — " .. tint("muted", "starting whispers"))
    for i = 1, sendCount do
        local fullName = eligible[i]
        ns.queueWhisper(opts.text, fullName)
        if skip then skip[fullName] = true end
        -- Only a timed -cd records new recipients; bare -cd just reads the pool.
        if cooldownBucket and cooldownMinutes then cooldownBucket[fullName] = time() end
    end
end

local listener = CreateFrame("Frame")
listener:RegisterEvent("CHAT_MSG_WHISPER")
listener:SetScript("OnEvent", function(_, _, _, sender)
    trackWhisper(sender)
end)

SLASH_REPLYRECENT1 = "/rr"
SlashCmdList["REPLYRECENT"] = replyRecent
