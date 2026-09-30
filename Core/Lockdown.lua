local _, ns = ...

-- Chat restrictions: the secret-value guard every payload reader asks first, the lockdown check every command asks before it starts, and the warning a running queue gets when a lockdown is coming.

-- Chat payloads and unit names turn secret inside restricted content. canaccessvalue asks whether the calling code may use a value, and Blizzard's own chat filter wrapper calls it under an addon's captured taint and reads the answer (ChatFrameFilters.lua), so it answers where issecretvalue might raise. Its argument is not nilable, and nil is never secret, so nil never reaches it.
local function canAccess(value)
    return value == nil or canaccessvalue(value)
end

-- The client's own answer to "are chat payloads secret right now" ("Returns true if API security restrictions regarding chat messaging are in effect"), which is exactly the condition that makes a whisper echo unreadable. Asking it beats deriving the answer from AddOnRestrictionType, where which values imply chat secrecy is only inferable from prose.
local function chatRestricted()
    return C_ChatInfo.InChatMessagingLockdown()
end

-- Every command refuses to start under a lockdown, and the queue stops a run that walks into one.
local function refuseRestricted()
    if not chatRestricted() then return false end
    ns.Fail("Chat restricted here.", "This content hides whisper echoes from addons. Leave it and retry.")
    return true
end

-- ADDON_RESTRICTION_STATE_CHANGED is the only warning a run gets that the rules are about to change. It fires before a restriction is enforced and after one is lifted, and an activating restriction is enforced once the event's dispatch completes, so the check is deferred a frame and then simply asks whether a chat lockdown is now in effect; a deactivation answers no and nothing happens. The payload names the restriction type, but which types hide chat is undocumented, so the payload is not read. Polling instead would notice a full echo timeout later, long enough to have recycled every whisper the lockdown swallowed.
local lockdownListeners = {}

function ns.OnChatLockdown(callback)
    lockdownListeners[#lockdownListeners + 1] = callback
end

local lockdownWatch = CreateFrame("Frame")
lockdownWatch:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED")
lockdownWatch:SetScript("OnEvent", function()
    C_Timer.After(0, function()
        if not chatRestricted() then return end
        for _, callback in ipairs(lockdownListeners) do callback() end
    end)
end)

ns.CanAccess = canAccess
ns.ChatRestricted = chatRestricted
ns.RefuseRestricted = refuseRestricted
