local _, ns = ...

-- One comparison rule for every player name the addon reads, because each source spells the same player its own way. Era gives "Name" or "Name-Realm". Forever gives a first name plus a surname, joined by " " in Blizzard's own unit names (Constants.CharacterNameSeparatorConsts) and accepted with " " or "-" by the whisper box (ChatFrameEditBox.lua ExtractTellTarget), while what /who, the whisper echo and the incoming whisper hand over is not pinned down by any source.
-- A key is the lowercased first name, plus "-" and the lowercased second part when there is one. Space and hyphen count as the same separator, and a third part (a realm behind a surname, or the tail of a hyphenated realm) is dropped, so no spelling can split one player into two keys.

local function nameKey(name)
    if type(name) ~= "string" then return nil end
    local first, second = name:match("^%s*([^%s%-]+)[%s%-]*([^%s%-]*)")
    if not first then return nil end
    if second == "" then return first:lower() end
    return first:lower() .. "-" .. second:lower()
end

local function firstPart(key)
    return key:match("^[^%-]+")
end

local function isFullKey(key)
    return key:find("-", 1, true) ~= nil
end

-- Two names are one player when their keys agree, or when either lacks its second part and the first names agree. Era drops the home realm and a Forever source may drop the surname, and a bare name can't be told apart from its full form.
local function sameName(a, b)
    local keyA, keyB = nameKey(a), nameKey(b)
    if not keyA or not keyB then return false end
    if keyA == keyB then return true end
    if isFullKey(keyA) and isFullKey(keyB) then return false end
    return firstPart(keyA) == firstPart(keyB)
end

-- The stored key a name resolves to in a table keyed by nameKey: the exact key, else its bare first name. Two lookups at most, so the long cooldown list can afford it on every /who row.
local function findKey(tbl, name)
    local key = nameKey(name)
    if not key then return nil end
    if tbl[key] ~= nil then return key end
    local first = firstPart(key)
    if first ~= key and tbl[first] ~= nil then return first end
    return nil
end

-- findKey plus the reverse, a bare name finding a stored full one. That takes a scan, so only the small session tables use it: the group, a run's recipients, the reply tracking.
local function findKeyScan(tbl, name)
    local found = findKey(tbl, name)
    if found then return found end
    local key = nameKey(name)
    if not key or isFullKey(key) then return nil end
    for stored in pairs(tbl) do
        if firstPart(stored) == key then return stored end
    end
    return nil
end

ns.NameKey = nameKey
ns.SameName = sameName
ns.FindKey = findKey
ns.FindKeyScan = findKeyScan
