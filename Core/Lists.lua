local _, ns = ...

-- The two persistent name lists and everything that reads them: the permanent block list and the expiring cooldown list.

-- A cooldown duration is a number with an optional unit: bare numbers are minutes, s m h d spell the rest. Zero and malformed input return nil so the caller can name the slip.
local DURATION_UNITS = { s = 1, m = 60, h = 3600, d = 86400 }
local DURATION_HINT = "Use 30 (minutes), 30m, 2h or 30d."

local function parseDuration(token)
    local amount, unit = token:match("^(%d+%.?%d*)([smhdSMHD]?)$")
    if not amount then return nil end
    local seconds = tonumber(amount) * DURATION_UNITS[unit == "" and "m" or unit:lower()]
    if not seconds or seconds <= 0 then return nil end
    return math.floor(seconds)
end

local function loadBlocked()
    SuperSocialDB = SuperSocialDB or {}

    -- Permanent, account-wide block list: keys are name keys (Core/Names.lua) so lookups ignore capitalization and separators, values keep the name as typed.
    local bucket = SuperSocialDB.blockedAccount or {}
    SuperSocialDB.blockedAccount = bucket
    return bucket
end

local function loadCooldowns()
    SuperSocialDB = SuperSocialDB or {}

    -- One account-wide cooldown list shared by every character, so a relog onto an alt keeps everyone's cooldown running. Keys are name keys, values the time the cooldown expires, so one list serves a 30-minute and a 30-day cooldown alike.
    local bucket = SuperSocialDB.cooldownAccount or {}
    SuperSocialDB.cooldownAccount = bucket

    -- Expired entries go on every load so the list can't grow without bound.
    local now = time()
    for name, expiry in pairs(bucket) do
        if expiry <= now then bucket[name] = nil end
    end
    return bucket
end

local function clearCooldowns()
    wipe(loadCooldowns())
end

-- A blocked or cooling name matches in both of its forms, so a hand-added bare "Name" still catches every "Name Surname" or "Name-Surname" that shares it.
local function isBlocked(blocked, name)
    return ns.FindKey(blocked, name) ~= nil
end

local function onCooldown(cooldowns, name)
    local key = ns.FindKey(cooldowns, name)
    return key ~= nil and cooldowns[key] > time()
end

ns.ParseDuration = parseDuration
ns.DurationHint = DURATION_HINT
ns.LoadBlocked = loadBlocked
ns.LoadCooldowns = loadCooldowns
ns.ClearCooldowns = clearCooldowns
ns.IsBlocked = isBlocked
ns.OnCooldown = onCooldown
