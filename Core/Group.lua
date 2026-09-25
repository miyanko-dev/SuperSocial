local _, ns = ...

-- Who counts as a groupmate for the /ww and /rr skip checks: the current party or raid, plus anyone who left it recently. Both sets are keyed by name key, so a Forever groupmate is told apart from a namesake with another surname.

local function buildGroupSet()
    local set = {}

    -- A hidden name can't be a table key, so a hidden groupmate is simply not in the set.
    local function add(unit)
        local key = ns.NameKey(ns.UnitFullName(unit))
        if key then set[key] = true end
    end
    add("player")
    if not IsInGroup() then return set end
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do add("raid" .. i) end
    else
        for i = 1, 4 do add("party" .. i) end
    end
    return set
end

-- A /who row or a reply names the player in whatever form its source uses, so the lookup accepts every spelling of the same key.
local function inGroup(set, name)
    return ns.FindKeyScan(set, name) ~= nil
end

-- People who left the group (or the whole group on disband) still count as groupmates for a while afterwards. The watcher diffs the roster on every change and stamps whoever vanished. Session-only, like the reply tracking.
local RECENT_GROUP_SECONDS = 15 * 60
local leftGroupAt = {}  -- name key -> time they left the group
local lastRoster = {}

local rosterWatcher = CreateFrame("Frame")
rosterWatcher:RegisterEvent("GROUP_ROSTER_UPDATE")
rosterWatcher:RegisterEvent("PLAYER_ENTERING_WORLD")
rosterWatcher:SetScript("OnEvent", function()
    local roster = buildGroupSet()
    for key in pairs(lastRoster) do
        if not roster[key] then
            leftGroupAt[key] = time()
        end
    end
    lastRoster = roster
    -- Sweep expired leavers on the same event, so the table can't grow all session between checks.
    local cutoff = time() - RECENT_GROUP_SECONDS
    for key, at in pairs(leftGroupAt) do
        if at < cutoff then leftGroupAt[key] = nil end
    end
end)

local function wasRecentlyGrouped(name)
    local key = ns.FindKeyScan(leftGroupAt, name)
    if not key then return false end
    if (time() - leftGroupAt[key]) >= RECENT_GROUP_SECONDS then
        leftGroupAt[key] = nil
        return false
    end
    return true
end

ns.BuildGroupSet = buildGroupSet
ns.InGroup = inGroup
ns.WasRecentlyGrouped = wasRecentlyGrouped
