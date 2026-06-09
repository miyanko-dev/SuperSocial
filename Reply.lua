local _, ns = ...

local tint = ns.tint
local status = ns.status
local detail = ns.detail
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
    local eligible = {}
    for name in pairs(whisperedAt) do
        local excluded = groupSet[ns.nameOnly(name)]
            or (skip and skip[name])
            or (cooldownBucket and not ns.isCool(cooldownBucket, name, opts.cooldownSeconds))
        if not excluded then
            eligible[#eligible + 1] = name
        end
    end
    table.sort(eligible, function(a, b) return whisperedAt[a] > whisperedAt[b] end)

    local sendCount = opts.limit and math.min(opts.limit, #eligible) or #eligible
    if sendCount == 0 then
        status(tint("skip", "Nobody to reply to") .. " — 0 of " .. total .. " eligible.")
        return
    end

    local skipped = total - sendCount

    if opts.preview then
        local line = tint("muted", "Preview") .. " — would reply to " .. sendCount .. " of " .. total .. " " .. plural(total, "whisperer", "whisperers")
        if skipped > 0 then
            line = line .. ", " .. tint("skip", skipped .. " skipped")
        end
        status(line .. ".")
        detail(tint("muted", "Message:") .. " " .. opts.text)
        return
    end

    for i = 1, sendCount do
        local fullName = eligible[i]
        ns.queueWhisper(opts.text, fullName)
        if skip then skip[fullName] = true end
        -- Only a timed -cd records new recipients; bare -cd just reads the pool.
        if cooldownBucket and cooldownMinutes then cooldownBucket[fullName] = time() end
    end

    local line = tint("sent", "Replying to " .. sendCount) .. " of " .. total .. " " .. plural(total, "whisperer", "whisperers")
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
