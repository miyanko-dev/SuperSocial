local _, ns = ...

-- Every place Classic Era 1.15.x and WoW Forever 1.60.x differ lives here, so a new build is checked against one file. One toc serves both clients; every difference is detected by feature at runtime, never by build number, interface version or WOW_PROJECT_ID.

-- 1.60 hands chat payloads and unit names out as secret values inside restricted content; 1.15.9 has the same predicate and never issues secrets, so one guard serves both.
-- 1.60 declares issecretvalue with SecretArguments "AllowedWhenUntainted" and Nilable = false; 1.15.9 declares the same function with no secret annotation at all. Whether the 1.60 flag makes it raise for tainted addon code is unsettled: Blizzard's own chat filter wrapper calls canaccessvalue under the addon's captured taint (ChatFrameFilters.lua). pcall makes the answer right either way, since a raise means secret, and nil is never secret, so it never reaches the predicate.
local isSecret = issecretvalue

local function canAccess(value)
    if value == nil or not isSecret then return true end
    local ok, secret = pcall(isSecret, value)
    return ok and not secret
end

-- The bare SendChatMessage global only exists while the loadDeprecationFallbacks CVar is on, on both builds. C_ChatInfo.SendChatMessage is the real API on both.
local sendChat = C_ChatInfo and C_ChatInfo.SendChatMessage or SendChatMessage

local function sendWhisper(text, target)
    sendChat(text, "WHISPER", nil, target)
end

-- The client's own answer to "are chat payloads secret right now". Documented identically on both builds as "Returns true if API security restrictions regarding chat messaging are in effect", which is exactly the condition that makes a whisper echo unreadable. Asking it beats deriving the same answer from AddOnRestrictionType, where which values imply chat secrecy is only inferable from prose.
local inChatLockdown = C_ChatInfo and C_ChatInfo.InChatMessagingLockdown

local function chatRestricted()
    return inChatLockdown ~= nil and inChatLockdown() == true
end

-- Every command refuses to start under a lockdown, and the queue stops a run that walks into one.
local function refuseRestricted()
    if not chatRestricted() then return false end
    ns.Fail("Chat restricted here.", "This content hides whisper echoes from addons. Leave it and retry.")
    return true
end

-- ADDON_RESTRICTION_STATE_CHANGED is the only warning a run gets that the rules are about to change. It fires before a restriction is enforced and after one is lifted, so the check is deferred a frame and then simply asks whether a chat lockdown is now in effect; a deactivation answers no and nothing happens. Polling instead would notice a full echo timeout later, long enough to have recycled every whisper the lockdown swallowed.
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

-- Blizzard's own invite, whisper and ignore menu builds a unit's name from UnitNameUnmodified and joins the second part the way the client reads it: a surname with the surname separator (" ") where regionally unique names are on, which is Forever (Mainline/UnitPopupUtils.lua GetFullPlayerName), a realm with "-" only across realms, which is Era (Classic/UnitPopupUtils.lua). Mirroring it gives /wt and the group check the exact string Blizzard would whisper. An empty second part is skipped, so a surname-less name never gains a trailing space.
local unitNameParts = UnitNameUnmodified or UnitName
local regionalNames = RegionalUniqueNamesEnabled
local separators = Constants and Constants.CharacterNameSeparatorConsts
local SURNAME_SEPARATOR = separators and separators.CHARACTERNAME_SURNAME_SEPARATOR or " "

-- Returns the unit's full name, or nil and true when the client hides it.
local function unitFullName(unit)
    local name, second = unitNameParts(unit)
    if not canAccess(name) or not canAccess(second) then return nil, true end
    if not name or name == "" then return nil end
    if not second or second == "" then return name end
    if regionalNames and regionalNames() then return name .. SURNAME_SEPARATOR .. second end
    if UnitRealmRelationship(unit) ~= LE_REALM_RELATION_SAME then return name .. "-" .. second end
    return name
end

-- The who list lives in the Friends window on 1.15.x and in the Group Finder's Who tab on 1.60. Each frame registers WHO_LIST_UPDATE itself, so both are candidates for deafening. Evaluated per call, because the 1.60 tab is load-on-demand.
local function whoListFrames()
    local frames = {}
    if FriendsFrame then frames[#frames + 1] = FriendsFrame end
    if LFGWhoListFrame then frames[#frames + 1] = LFGWhoListFrame end
    return frames
end

local function whoPanelShown()
    if WhoFrame and WhoFrame:IsShown() then return true end
    return LFGWhoListFrame ~= nil and LFGWhoListFrame:IsShown()
end

-- The chat filter moved into ChatFrameUtil on both clients; the bare global only survives behind the deprecation fallback CVar.
local addChatFilter = ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter or ChatFrame_AddMessageEventFilter

-- Era's auction house still reports each row's seller; Forever's modern auction house exposes no seller at all, so /ws exists only where both of these calls do. The 15th return carries the realm, the 14th doesn't (Classic/Blizzard_AuctionUI.lua, the Browse list update).
local getNumAuctions = GetNumAuctionItems
local getAuctionInfo = GetAuctionItemInfo

-- Every seller on the current Browse page in listing order, duplicates included; the command decides who qualifies.
local function auctionSellers()
    local sellers = {}
    local count = getNumAuctions("list") or 0
    for i = 1, count do
        local owner, ownerFullName = select(14, getAuctionInfo("list", i))
        local name = ownerFullName or owner
        if name and name ~= "" then sellers[#sellers + 1] = name end
    end
    return sellers
end

-- The Browse page only means something while the auction house is open; AuctionFrame is Era's load-on-demand window.
local function auctionHouseShown()
    return AuctionFrame ~= nil and AuctionFrame:IsShown()
end

ns.CanAccess = canAccess
ns.SendWhisper = sendWhisper
ns.ChatRestricted = chatRestricted
ns.RefuseRestricted = refuseRestricted
ns.UnitFullName = unitFullName
ns.WhoListFrames = whoListFrames
ns.WhoPanelShown = whoPanelShown
ns.AddChatFilter = addChatFilter
if getNumAuctions and getAuctionInfo then
    ns.AuctionSellers = auctionSellers
    ns.AuctionHouseShown = auctionHouseShown
end
