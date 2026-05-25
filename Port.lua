local PREFIX = "|cffffff00[Whisper Them All!]:|r "
local DEFAULT_N = 5
local WHO_TIMEOUT = 6
local CONFIRM_DIALOG = "WHISPERTHEMALL_CONFIRM_WHISPERS"

local function notify(msg)
    print(PREFIX .. msg)
end

StaticPopupDialogs[CONFIRM_DIALOG] = {
    text = "Send whispers to %d player(s)?\n\nMessage that will be sent:\n|cffffd200%s|r",
    button1 = "Send",
    button2 = CANCEL,
    OnAccept = function(self, data)
        if not data or not data.plan then return end
        for i = 1, #data.plan do
            local item = data.plan[i]
            SendChatMessage(item.message, "WHISPER", nil, item.name)
        end
        notify(string.format("Sending message to %d player%s.",
            #data.plan, #data.plan == 1 and "" or "s"))
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- Each entry has:
--   keys        : aliases the user can type (lower-case, may contain spaces)
--   display     : zone name used in whisper messages (preserved capitalisation)
--   search      : zone string passed to /who; fall back to a parent zone when
--                 the requested location is a subzone /who can't resolve
--   magePortal  : true only for the six capitals mages can portal to
--
-- Add new subzone or hub entries below with magePortal = false and a search
-- value pointing at the parent zone that /who actually returns results for.
local ZONES = {
    { keys = { "darnassus", "dar" },                              display = "Darnassus",     search = "Darnassus",      magePortal = true  },
    { keys = { "stormwind", "sw" },                               display = "Stormwind",     search = "Stormwind City", magePortal = true  },
    { keys = { "ironforge", "if" },                               display = "Ironforge",     search = "Ironforge",      magePortal = true  },
    { keys = { "orgrimmar", "org" },                              display = "Orgrimmar",     search = "Orgrimmar",      magePortal = true  },
    { keys = { "thunder bluff", "thunderbluff", "thunder", "tb" },display = "Thunder Bluff", search = "Thunder Bluff",  magePortal = true  },
    { keys = { "undercity", "uc" },                               display = "Undercity",     search = "Undercity",      magePortal = true  },

    { keys = { "booty bay", "bootybay", "bb" },                   display = "Booty Bay",     search = "Stranglethorn",  magePortal = false },
}

local MAGE_TEMPLATES = {
    "Hey {name}! Sorry to bug you, any chance for a quick port to {zone} please? Happy to tip, no worries if busy :) <3",
    "Hiya {name}! Could I grab a port to {zone} when you have a sec? Tip ready ofc, totally fine if not :) <3",
    "Hey {name}! Would you be able to toss me a port to {zone} please? I'll tip, and no stress if now's bad :)",
    "Hey {name}! Any chance I could get a portal to {zone} real quick? Happy to tip for your time :) <3",
    "Hi {name}! Sorry to bother, could I please get a port to {zone}? Got a tip ready, no worries if you're busy :)",
    "Hey {name}! If you're not in the middle of something, could I get a quick port to {zone} please? Tip ofc :) <3",
    "Hey {name}! Could I bother you for a portal to {zone} please? Happy to tip, no worries either way :)",
    "Hiya {name} :) Any chance for a quick port to {zone}? I'll gladly tip, and all good if you can't right now <3",
    "Hey {name}! Sorry for the whisper, could I get a port to {zone} please? Tip ready, ty either way :)",
    "Heya {name}! Could you maybe hook me up with a portal to {zone}? Happy to tip, and no worries if not :) <3",
}

local WARLOCK_TEMPLATES = {
    "Hey {name}! Sorry to bug you, any chance for a summon to {zone} please? I can help find clickers too :) <3",
    "Hiya {name}! Could I maybe grab a summon to {zone} when you have a sec? Happy to help with clicks :)",
    "Hey {name}! Any chance for a quick summon to {zone} please? I can help get clickers, no worries if busy :)",
    "Hey {name}! Would you be able to summon me to {zone} please? I'll help find clickers if needed :) <3",
    "Hi {name}! Sorry for the whisper, could I get a summon to {zone}? I can grab clickers too, all good if not :)",
    "Heya {name}! Any chance you could summon me to {zone}? I'll help with clicks ofc :) <3",
    "Hey {name}! Could I bother you for a summon to {zone} please? I can help sort clickers, no stress if not :)",
    "Hiya {name} :) Could I maybe get a summon to {zone}? Happy to help find clickers too <3",
    "Hey {name}! If you've got a sec, could I get a summon to {zone} please? I can help with the clicks :)",
    "Hey {name}! Any chance for a quick summon to {zone}? I'll help get clickers, ty either way :) <3",
}

local CLICKER_TEMPLATES = {
    "Hey {name}! Sorry to bug you, could you help us with a quick summon click in {zone} please? Lock is ready :) <3",
    "Hiya {name}! Any chance you could click a summon real quick in {zone}? We've got the lock set up, ty either way :)",
    "Hey {name}! Could you help with one summon click in {zone} please? Takes a sec, no worries if busy :) <3",
    "Hey {name}! Sorry to bother, could you click our summon in {zone} real quick? Lock's ready :)",
    "Hi {name}! Any chance for a quick summon click in {zone}? We just need one more clicker, ty either way :) <3",
    "Heya {name}! Could you help us click a summon in {zone} please? Super quick, no stress if you can't :)",
    "Hey {name}! Sorry for the whisper, could you click a summon for us real quick in {zone}? Lock is here :) <3",
    "Hiya {name} :) Could you help with a summon click in {zone} please? Takes just a moment, no worries if not :)",
    "Hey {name}! We've got a lock ready in {zone}, could you help click a summon real quick? Ty either way :) <3",
    "Hey {name}! Any chance you could be a summon clicker for a sec in {zone}? Lock's ready, super quick :)",
}

local CLASS_NAMES_MALE = LOCALIZED_CLASS_NAMES_MALE or {}
local CLASS_NAMES_FEMALE = LOCALIZED_CLASS_NAMES_FEMALE or {}
local MAGE_LOC_M = CLASS_NAMES_MALE.MAGE or "Mage"
local MAGE_LOC_F = CLASS_NAMES_FEMALE.MAGE or MAGE_LOC_M
local WARLOCK_LOC_M = CLASS_NAMES_MALE.WARLOCK or "Warlock"
local WARLOCK_LOC_F = CLASS_NAMES_FEMALE.WARLOCK or WARLOCK_LOC_M

local function classToken(info)
    if not info then return nil end
    if info.filename then return info.filename end
    local s = info.classStr
    if not s then return nil end
    if s == MAGE_LOC_M or s == MAGE_LOC_F then return "MAGE" end
    if s == WARLOCK_LOC_M or s == WARLOCK_LOC_F then return "WARLOCK" end
    return s
end

local function trim(s)
    return (s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function pickRandom(list)
    return list[math.random(#list)]
end

local function fillTemplate(template, fullName, zone)
    local short = fullName:match("^([^-]+)") or fullName
    return (template:gsub("{name}", short):gsub("{zone}", zone))
end

local function titleCase(text)
    return (text:gsub("(%a)(%w*)", function(first, rest)
        return first:upper() .. rest:lower()
    end))
end

-- Greedy longest-prefix match against ZONES. Returns zoneObj, leftoverText.
-- When the input doesn't start with a known alias, falls back to the first
-- whitespace-separated token as an unknown zone (search = display = that token).
local function matchZonePrefix(text)
    text = trim(text)
    if text == "" then return nil, "" end

    local lc = text:lower()
    local bestZone, bestEnd
    for _, zone in ipairs(ZONES) do
        for _, key in ipairs(zone.keys) do
            local klen = #key
            if lc:sub(1, klen) == key then
                local after = lc:sub(klen + 1, klen + 1)
                if after == "" or after == " " then
                    if not bestEnd or klen > bestEnd then
                        bestZone = zone
                        bestEnd = klen
                    end
                end
            end
        end
    end

    if bestZone then
        return bestZone, trim(text:sub(bestEnd + 1))
    end

    local first, rest = text:match("^(%S+)%s*(.*)$")
    if not first then return nil, "" end
    local unknown = {
        display = titleCase(first),
        search = first,
        magePortal = false,
    }
    return unknown, trim(rest or "")
end

-- /port:     [N] ZONE                  (no MESSAGE; ZONE consumes the rest)
-- /clickers: [N] ZONE [MESSAGE]        (greedy zone match, leftover = MESSAGE)
local function parseCommand(input, hasMessage)
    input = trim(input)
    local n
    local nStr, rest = input:match("^(%d+)%s+(.*)$")
    if nStr then
        n = tonumber(nStr)
        input = rest or ""
    end

    if hasMessage then
        local zone, leftover = matchZonePrefix(input)
        return n, zone, leftover
    else
        input = input:gsub("^%-", "")
        local zone = matchZonePrefix(input)
        return n, zone, nil
    end
end

local function zoneListString()
    local out = {}
    for _, z in ipairs(ZONES) do
        out[#out + 1] = z.display
    end
    return table.concat(out, ", ")
end

local pending
local watcher
local timeoutTimer

local function clearPending()
    pending = nil
    if watcher then watcher:UnregisterAllEvents() end
    if timeoutTimer then timeoutTimer:Cancel() end
    timeoutTimer = nil
end

-- Build the (name, message) list a /port run would send. Returns nil when no
-- eligible recipient was found so the caller can notify and skip the dialog.
local function planPort(ctx, mages, warlocks)
    local plan = {}
    if ctx.zone.magePortal then
        local mageCount = math.min(ctx.n, #mages)
        for i = 1, mageCount do
            local name = mages[i]
            local msg = fillTemplate(pickRandom(MAGE_TEMPLATES), name, ctx.zone.display)
            plan[#plan + 1] = { name = name, message = msg }
        end
    end
    local warlockCount = math.min(ctx.n, #warlocks)
    for i = 1, warlockCount do
        local name = warlocks[i]
        local msg = fillTemplate(pickRandom(WARLOCK_TEMPLATES), name, ctx.zone.display)
        plan[#plan + 1] = { name = name, message = msg }
    end

    if #plan == 0 then
        if ctx.zone.magePortal then
            notify(string.format("No mages or warlocks found in %s.", ctx.zone.display))
        else
            notify(string.format("No warlocks found in %s.", ctx.zone.display))
        end
        return nil
    end
    return plan
end

local function planClickers(ctx, candidates)
    local n = math.min(ctx.n, #candidates)
    if n == 0 then
        notify(string.format("No eligible clickers found in %s.", ctx.zone.display))
        return nil
    end
    local plan = {}
    for i = 1, n do
        local name = candidates[i]
        local template = ctx.customMessage or pickRandom(CLICKER_TEMPLATES)
        plan[#plan + 1] = { name = name, message = fillTemplate(template, name, ctx.zone.display) }
    end
    return plan
end

-- Show a native confirmation popup. The preview uses the first planned message;
-- /port mage+warlock runs will show a mage sample when both are present.
local function confirmAndSend(plan)
    StaticPopup_Show(CONFIRM_DIALOG, #plan, plan[1].message, { plan = plan })
end

local function onWhoComplete()
    if not pending then return end
    local ctx = pending
    clearPending()
    C_FriendList.SetWhoToUi(true)

    local count = C_FriendList.GetNumWhoResults() or 0
    local me = UnitName("player")
    local mages, warlocks, others = {}, {}, {}
    for i = 1, count do
        local info = C_FriendList.GetWhoInfo(i)
        local fullName = info and info.fullName
        if fullName and fullName ~= me then
            local token = classToken(info)
            if token == "MAGE" then
                mages[#mages + 1] = fullName
            elseif token == "WARLOCK" then
                warlocks[#warlocks + 1] = fullName
            else
                others[#others + 1] = fullName
            end
        end
    end

    local plan
    if ctx.mode == "port" then
        plan = planPort(ctx, mages, warlocks)
    else
        local pool = {}
        for _, n in ipairs(mages) do pool[#pool + 1] = n end
        for _, n in ipairs(others) do pool[#pool + 1] = n end
        plan = planClickers(ctx, pool)
    end
    if plan then confirmAndSend(plan) end
end

local function startWho(zone, mode, n, customMessage)
    if pending then
        notify("Another /port or /clickers query is in flight, please wait.")
        return
    end
    pending = { zone = zone, mode = mode, n = n, customMessage = customMessage }

    if not watcher then
        watcher = CreateFrame("Frame")
        watcher:SetScript("OnEvent", onWhoComplete)
    end
    watcher:RegisterEvent("WHO_LIST_UPDATE")

    local query
    if zone.search:find(" ") then
        query = string.format('z-"%s"', zone.search)
    else
        query = "z-" .. zone.search
    end
    C_FriendList.SetWhoToUi(false)
    C_FriendList.SendWho(query)

    timeoutTimer = C_Timer.NewTimer(WHO_TIMEOUT, function()
        if pending and pending.zone == zone then
            clearPending()
            C_FriendList.SetWhoToUi(true)
            notify("/who query timed out -- try again in a few seconds.")
        end
    end)
end

local function handlePort(input)
    local n, zone = parseCommand(input or "", false)
    if not zone then
        notify("Usage: /port [N] ZONE   Known zones: " .. zoneListString())
        return
    end
    startWho(zone, "port", n or DEFAULT_N, nil)
end

local function handleClickers(input)
    local n, zone, message = parseCommand(input or "", true)
    if not zone then
        notify("Usage: /clickers [N] ZONE [MESSAGE]   Known zones: " .. zoneListString())
        return
    end
    local customMessage
    if message and message ~= "" then customMessage = message end
    startWho(zone, "clickers", n or DEFAULT_N, customMessage)
end

SLASH_WHISPERTHEMALLPORT1 = "/port"
SlashCmdList["WHISPERTHEMALLPORT"] = handlePort

SLASH_WHISPERTHEMALLCLICKERS1 = "/clickers"
SLASH_WHISPERTHEMALLCLICKERS2 = "/clicker"
SlashCmdList["WHISPERTHEMALLCLICKERS"] = handleClickers
