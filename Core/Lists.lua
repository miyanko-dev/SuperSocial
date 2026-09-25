local ADDON, ns = ...

-- The two persistent name lists and everything that reads or reshapes them: the permanent block list, the expiring cooldown list, and the migration that folded the old ignore list into the latter.

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

    -- Expired entries go on every load so the list can't grow without bound; a non-number is pre-migration debris and goes too.
    local now = time()
    for name, expiry in pairs(bucket) do
        if type(expiry) ~= "number" or expiry <= now then bucket[name] = nil end
    end
    return bucket
end

local function clearCooldowns()
    wipe(loadCooldowns())
end

-- A blocked or cooling name matches in both of its forms, so a hand-added bare "Name" still catches every "Name-Realm" or "First Surname" that shares it.
local function isBlocked(blocked, name)
    return ns.FindKey(blocked, name) ~= nil
end

local function onCooldown(cooldowns, name)
    local key = ns.FindKey(cooldowns, name)
    return key ~= nil and cooldowns[key] > time()
end

-- Saved variables are never rewritten wholesale, so a removed feature's data sits in the file forever unless it is dropped by name. These are all that is left of a chat scanner, a login banner and the per-character lists.
local DEAD_KEYS = { "chatScan", "showLoginBanner", "ignoredByChar", "ignored", "cooldownByChar" }

local COOLDOWN_FORMAT = 2          -- Bumped when the cooldown list changes shape, so the conversion below runs once.
local NAME_KEY_FORMAT = 2          -- Bumped when stored name keys change shape, so the re-key below runs once.
local IGNORE_DAYS = 30             -- The old ignore list aged entries out after this long.
local LEGACY_COOLDOWN_GRACE = 3600 -- Old cooldown stamps carried no duration; an hour keeps a run in progress honest without holding names for long.

-- Cooldowns used to store the send time and apply the duration when read, and the ignore list was a separate 30-day memory. Both fold into one list of expiry times: ignore entries keep the rest of their 30 days, old cooldown stamps get an hour.
local function migrateCooldowns(db)
    if (db.cooldownFormat or 1) >= COOLDOWN_FORMAT then return end
    local merged = {}
    local function keep(name, expiry)
        local key = name:lower()
        merged[key] = math.max(merged[key] or 0, expiry)
    end
    for name, stamp in pairs(db.cooldownAccount or {}) do
        if type(stamp) == "number" then keep(name, stamp + LEGACY_COOLDOWN_GRACE) end
    end
    for name, stamp in pairs(db.ignoredAccount or {}) do
        if type(stamp) == "number" then keep(name, stamp + IGNORE_DAYS * 86400) end
    end
    db.cooldownAccount = merged
    db.ignoredAccount = nil
    db.cooldownFormat = COOLDOWN_FORMAT
end

-- Both lists used to key on the lowercased name as typed or listed. Re-keying through ns.NameKey folds "First Surname" and "First-Surname" into one entry; a blocked name keeps its display value, a cooldown keeps the later expiry.
local function rekeyNames(db)
    if (db.nameKeyFormat or 1) >= NAME_KEY_FORMAT then return end
    local blocked = {}
    for name, shown in pairs(db.blockedAccount or {}) do
        local key = ns.NameKey(name)
        if key then blocked[key] = shown end
    end
    local cooldowns = {}
    for name, expiry in pairs(db.cooldownAccount or {}) do
        local key = ns.NameKey(name)
        if key and type(expiry) == "number" then cooldowns[key] = math.max(cooldowns[key] or 0, expiry) end
    end
    db.blockedAccount = blocked
    db.cooldownAccount = cooldowns
    db.nameKeyFormat = NAME_KEY_FORMAT
end

local dbCleanup = CreateFrame("Frame")
dbCleanup:RegisterEvent("ADDON_LOADED")
dbCleanup:SetScript("OnEvent", function(self, _, addon)
    if addon ~= ADDON then return end
    self:UnregisterAllEvents()
    SuperSocialDB = SuperSocialDB or {}
    for _, key in ipairs(DEAD_KEYS) do SuperSocialDB[key] = nil end
    migrateCooldowns(SuperSocialDB)
    rekeyNames(SuperSocialDB)
end)

ns.ParseDuration = parseDuration
ns.DurationHint = DURATION_HINT
ns.LoadBlocked = loadBlocked
ns.LoadCooldowns = loadCooldowns
ns.ClearCooldowns = clearCooldowns
ns.IsBlocked = isBlocked
ns.OnCooldown = onCooldown
ns.MigrateCooldowns = migrateCooldowns
