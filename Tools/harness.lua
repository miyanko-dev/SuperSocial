-- Stub WoW Forever client for SuperSocial. Loads the toc file list in order and drives the slash
-- commands in a 1.60.1-shaped environment. Proves load order, API surface and control flow only; it
-- is not a client and proves nothing about in-game behaviour.

local ADDON_DIR = arg[1] or "."
-- How the secret predicates treat a secret from tainted code, which no source settles: strict raises, lenient answers.
local SECRETS = arg[2] or "strict" -- strict | lenient

--=== clock and scheduler ====================================================
local now = 1000.0
local wallclock = 1700000000
local timers = {}

local function schedule(delay, fn)
    local t = { at = now + delay, fn = fn, cancelled = false }
    timers[#timers + 1] = t
    return t
end

local function runTimers(untilTime)
    while true do
        local best, bestIndex
        for i, t in ipairs(timers) do
            if not t.cancelled and t.at <= untilTime and (not best or t.at < best.at) then
                best, bestIndex = t, i
            end
        end
        if not best then break end
        table.remove(timers, bestIndex)
        now = math.max(now, best.at)
        wallclock = math.floor(1700000000 + (now - 1000))
        best.fn()
    end
    now = math.max(now, untilTime)
end

--=== output =================================================================
local lines = {}
local function out(msg)
    msg = msg:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    lines[#lines + 1] = msg
    print("  " .. msg)
end

--=== frames and events ======================================================
local frames = {}
local function fire(event, ...)
    for _, f in ipairs(frames) do
        if f._events[event] and f._onEvent then f._onEvent(f, event, ...) end
    end
end

local function newFrame()
    local f = { _events = {}, _shown = false, _points = {}, _scripts = {} }
    function f:RegisterEvent(e) self._events[e] = true end
    function f:UnregisterEvent(e) self._events[e] = nil end
    function f:IsEventRegistered(e) return self._events[e] == true end
    function f:SetScript(name, fn)
        self._scripts[name] = fn
        if name == "OnEvent" then self._onEvent = fn end
    end
    function f:Show() self._shown = true end
    function f:Hide() self._shown = false end
    function f:SetShown(shown) self._shown = shown and true or false end
    function f:IsShown() return self._shown end
    function f:IsVisible() return self._shown and (not self._parent or self._parent:IsVisible()) end
    function f:SetPoint(point, ...) self._points[point] = { ... } end
    function f:SetSize() end
    function f:SetWidth() end
    function f:SetHeight() end
    function f:GetWidth() return 420 end
    function f:GetHeight() return 100 end
    function f:SetFrameStrata(strata) self._strata = strata end
    function f:SetToplevel() end
    function f:SetClampedToScreen() end
    function f:SetMovable() end
    function f:EnableMouse() end
    function f:RegisterForDrag() end
    function f:StartMoving() end
    function f:StopMovingOrSizing() end
    function f:SetScrollChild() end
    function f:SetJustifyH() end
    function f:SetWordWrap() end
    function f:SetText(text) self._text = text end
    function f:GetStringHeight() return 12 end
    function f:CreateFontString() return newFrame() end
    frames[#frames + 1] = f
    return f
end

--=== template-provided children ============================================
-- ButtonFrameTemplate hands the frame a portrait, a TitleContainer, a CloseButton and its Inset
-- (PortraitFrameMixin, SharedUIPanelTemplates.xml), and ScrollFrameTemplate builds an 8 px wide
-- MinimalScrollBar in its OnLoad; the stub supplies them too.
local scrollFrames = {}
local KNOWN_TEMPLATES = {
    ButtonFrameTemplate = function(f)
        f.TitleContainer = newFrame(); f.CloseButton = newFrame(); f.Inset = newFrame()
        function f:SetPortraitToAsset(texture) self._portrait = texture end
        function f:SetTitle(title) self._title = title end
    end,
    InsetFrameTemplate = function(f) f.NineSlice = newFrame() end,
    ScrollFrameTemplate = function(f)
        f.ScrollBar = newFrame()
        function f.ScrollBar:GetWidth() return 8 end
        scrollFrames[#scrollFrames + 1] = f
    end,
}

_G = _ENV or _G

function CreateFrame(_, name, _, template)
    local f = newFrame()
    if template then
        for word in tostring(template):gmatch("[^,%s]+") do
            assert(KNOWN_TEMPLATES[word], "unknown template: " .. word)
            KNOWN_TEMPLATES[word](f)
        end
    end
    if name then _G[name] = f end
    return f
end

--=== shared globals =========================================================
UIParent = newFrame()
UISpecialFrames = {}
-- Newest line last, the order a ScrollingMessageFrame's history reads, so TransformMessages can rewrite a line in place.
local chatHistory = {}
DEFAULT_CHAT_FRAME = {
    AddMessage = function(_, msg)
        chatHistory[#chatHistory + 1] = msg
        out(msg)
    end,
    TransformMessages = function(_, predicate, transform)
        for i, msg in ipairs(chatHistory) do
            if predicate(msg) then chatHistory[i] = transform(msg) end
        end
    end,
}
-- The client builds its colour objects from C_UIColor.GetColors() at load; the shades here are
-- stand-ins, only the wrapping is modelled.
local function colorObject(hex)
    return { WrapTextInColorCode = function(_, text) return "|cff" .. hex .. text .. "|r" end }
end
NORMAL_FONT_COLOR = colorObject("ffd100")
YELLOW_FONT_COLOR = colorObject("ffff00")
GREEN_FONT_COLOR = colorObject("19ff19")
RED_FONT_COLOR = colorObject("ff2020")
LIGHTBLUE_FONT_COLOR = colorObject("88aaff")
ColorManager = {
    GetColorDataForItemQuality = function(quality)
        if quality == nil then return nil end
        return { color = colorObject("ffffff") }
    end,
}
PANEL_INSET_LEFT_OFFSET = 4
PANEL_INSET_RIGHT_OFFSET = -6
SCROLL_FRAME_SCROLL_BAR_OFFSET_LEFT = 6
function ButtonFrameTemplate_HideButtonBar(frame) frame._buttonBarHidden = true end

function GetTime() return now end
function time() return wallclock end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function tinsert(t, v) t[#t + 1] = v end

C_Timer = {
    After = function(delay, fn) schedule(delay, fn) end,
    NewTimer = function(delay, fn)
        local t = schedule(delay, fn)
        return { Cancel = function() t.cancelled = true end }
    end,
}

--=== group ==================================================================
-- Units answer (name, second): the second part is a surname where regionally unique names are on,
-- else a realm, which a same-realm unit leaves nil.
local groupRoster = {}
local regionalNames = true
function IsInGroup() return #groupRoster > 0 end
function IsInRaid() return false end
function GetNumGroupMembers() return #groupRoster end
local function unitParts(unit)
    if unit == "player" then return "Selfy", "Mcself" end
    if unit == "target" then return TARGET_NAME, TARGET_SECOND end
    local index = unit:match("^party(%d)$")
    local member = index and groupRoster[tonumber(index)]
    if member then return member[1], member[2] end
    return nil
end
UnitNameUnmodified = unitParts
function RegionalUniqueNamesEnabled() return regionalNames end
Constants = { CharacterNameSeparatorConsts = { CHARACTERNAME_LINK_SEPARATOR = "-", CHARACTERNAME_REALMNAME_SEPARATOR = "-", CHARACTERNAME_SURNAME_SEPARATOR = " " } }
LE_REALM_RELATION_SAME = 1
function UnitRealmRelationship(unit)
    if unit == "target" and TARGET_CROSS_REALM then return 2 end
    return LE_REALM_RELATION_SAME
end
function UnitExists(unit) return unit ~= "target" or TARGET_NAME ~= nil end
function UnitIsPlayer() return true end

--=== chat ===================================================================
local whisperLog = {}
local chatFilters = {}
local deliveryMode = "echo" -- echo | silent | notfound | ambiguous | throttle
-- The echo may spell the recipient differently from the send; scenarios swap this to prove the match survives it.
local echoName = function(target) return target end

-- Only the namespaced call: the bare SendChatMessage global needs the loadDeprecationFallbacks CVar.
local function sendChatMessage(text, kind, _, target)
    whisperLog[#whisperLog + 1] = { text = text, kind = kind, target = target }
    if deliveryMode == "silent" then return end
    schedule(0.01, function()
        if deliveryMode == "echo" then
            fire("CHAT_MSG_WHISPER_INFORM", text, echoName(target))
        elseif deliveryMode == "notfound" then
            fire("CHAT_MSG_SYSTEM", "No player named '" .. target .. "' is currently playing.")
        elseif deliveryMode == "ambiguous" then
            fire("CHAT_MSG_SYSTEM", target .. ": More than one player matches, type more of their server name")
        elseif deliveryMode == "throttle" then
            fire("CHAT_MSG_SYSTEM", "The number of messages that can be sent is limited, please wait to send another message.")
        end
    end)
end

ERR_CHAT_THROTTLED = "The number of messages that can be sent is limited, please wait to send another message."
ERR_CHAT_PLAYER_NOT_FOUND_S = "No player named '%s' is currently playing."
ERR_IGNORING_YOU_S = "%s is ignoring you."
ERR_CHAT_PLAYER_AMBIGUOUS_S = "%s: More than one player matches, type more of their server name"
ERR_CHAT_RESTRICTED = "Free Trial accounts cannot send unlimited tells. You must wait before you can send tells to more players.  |cffffd000|Hstorecategory:gametime|h[Click To Upgrade]|h|r"
ERR_CHAT_RESTRICTED_TRIAL = ERR_CHAT_RESTRICTED

--=== who list ===============================================================
local whoResults = {}
local whoToUi = false
-- RequiresFriendList: the who calls return nothing while the friend list is unavailable.
local friendListReady = true
C_FriendList = {
    GetNumWhoResults = function()
        if not friendListReady then return end
        return #whoResults, #whoResults
    end,
    GetWhoInfo = function(i) return whoResults[i] end,
    SetWhoToUi = function(v) whoToUi = v end,
    SendWho = function()
        schedule(0.5, function() fire("WHO_LIST_UPDATE") end)
    end,
}

--=== auction house =========================================================
-- Search results by item ID. Rows carry owners the way ItemSearchResultInfo and
-- CommoditySearchResultInfo do: "player" for your own auction, and a totalNumberOfOwners past
-- #owners for sellers the row leaves unnamed. Every argument is declared Nilable = false.
local itemResults, commodityResults = {}, {}
local itemNames = { [2589] = "Linen Cloth", [4306] = "Silk Cloth" }
C_AuctionHouse = {
    GetNumItemSearchResults = function(itemKey)
        assert(type(itemKey) == "table", "bad argument #1: itemKey expected")
        return #(itemResults[itemKey.itemID] or {})
    end,
    GetItemSearchResultInfo = function(itemKey, index)
        assert(type(itemKey) == "table" and index, "bad argument: itemKey and index expected")
        return (itemResults[itemKey.itemID] or {})[index]
    end,
    GetNumCommoditySearchResults = function(itemID)
        assert(type(itemID) == "number", "bad argument #1: itemID expected")
        return #(commodityResults[itemID] or {})
    end,
    GetCommoditySearchResultInfo = function(itemID, index)
        assert(type(itemID) == "number" and index, "bad argument: itemID and index expected")
        return (commodityResults[itemID] or {})[index]
    end,
    MakeItemKey = function(itemID)
        return { itemID = itemID, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 }
    end,
    -- Nil until the client has cached the item.
    GetItemKeyInfo = function(itemKey)
        local name = itemNames[itemKey.itemID]
        if not name then return nil end
        return { itemID = itemKey.itemID, itemName = name, quality = 1 }
    end,
}

--=== slash commands =========================================================
SlashCmdList = {}

--=== client surface =======================================================
-- The Who tab is the load-on-demand LFGWhoListFrame inside LFGParentFrame, ChatFrameUtil is the
-- filter API, and chat payloads go secret under a lockdown.
local restrictionActive = false
local secretValues = {}

LFGParentFrame = newFrame()
LFGWhoListFrame = newFrame()
LFGWhoListFrame._parent = LFGParentFrame
LFGWhoListFrame:RegisterEvent("WHO_LIST_UPDATE")
ChatFrameUtil = {
    AddMessageEventFilter = function(event, fn) chatFilters[event] = fn end,
}

-- The argument is declared Nilable = false, so nil raises. Strict issecretvalue never answers for a
-- secret. canaccessvalue always answers, because Blizzard's chat filter wrapper calls it under addon
-- taint and reads the result (ChatFrameFilters.lua).
local function secretPredicate(answerSecret, mayRaise)
    return function(value)
        assert(value ~= nil, "bad argument #1: value expected")
        if secretValues[value] then
            if mayRaise and SECRETS == "strict" then error("Secret values are only allowed during untainted execution for this argument.") end
            return answerSecret
        end
        return not answerSecret
    end
end
issecretvalue = secretPredicate(true, true)
canaccessvalue = secretPredicate(false, false)

Enum = {
    AddOnRestrictionType = { Combat = 0, Encounter = 1, ChallengeMode = 2, PvPMatch = 3, Map = 4, Chat = 5 },
    AddOnRestrictionState = { Inactive = 0, Activating = 1, Active = 2 },
}

-- The addon asks this rather than mapping restriction types itself.
C_ChatInfo = {
    InChatMessagingLockdown = function() return restrictionActive end,
    SendChatMessage = sendChatMessage,
}

--=== load the addon in toc order ===========================================
-- A first install has no saved variables at all.
SuperSocialDB = nil

local ns = {}
local function loadToc(tocPath)
    local order = {}
    for raw in io.lines(tocPath) do
        local line = raw:gsub("%s+$", "")
        if line ~= "" and not line:match("^#") then order[#order + 1] = (line:gsub("\\", "/")) end
    end
    for _, rel in ipairs(order) do
        local path = ADDON_DIR .. "/" .. rel
        local chunk, err = loadfile(path)
        assert(chunk, err)
        chunk("SuperSocial", ns)
    end
    return order
end

local order = loadToc(ADDON_DIR .. "/SuperSocial.toc")
print(("== %s secrets: loaded %d files =="):format(SECRETS, #order))

fire("ADDON_LOADED", "SuperSocial")
fire("PLAYER_ENTERING_WORLD")
runTimers(now + 1)

--=== scenarios ==============================================================
local failures = 0
local function expect(label, condition, detail)
    if condition then
        print(("  [pass] %s"):format(label))
    else
        failures = failures + 1
        print(("  [FAIL] %s %s"):format(label, detail or ""))
    end
end

local function resetRun()
    lines = {}
    whisperLog = {}
    deliveryMode = "echo"
    echoName = function(target) return target end
end

local function seen(pattern)
    for _, l in ipairs(lines) do if l:find(pattern) then return true end end
    return false
end

local function setWho(names)
    whoResults = {}
    for _, n in ipairs(names) do
        whoResults[#whoResults + 1] = { fullName = n, classStr = "Mage", area = "Stormwind" }
    end
end

local function targetOf(index)
    return tostring(whisperLog[index] and whisperLog[index].target)
end

print("\n-- first load needs no saved variables --")
expect("loading wrote no saved variables", SuperSocialDB == nil)

print("\n-- chat lines wear Blizzard's colour objects --")
local literal = {}
for _, rel in ipairs(order) do
    local lineNo = 0
    for text in io.lines(ADDON_DIR .. "/" .. rel) do
        lineNo = lineNo + 1
        if text:find("|c%x") or text:find("\"|c\"", 1, true) or text:find("\"%x%x%x%x%x%x%x%x\"") then
            literal[#literal + 1] = rel .. ":" .. lineNo
        end
    end
end
expect("no literal colour codes in the addon", #literal == 0, table.concat(literal, ", "))
resetRun()
chatHistory = {}
SlashCmdList["SUPERSOCIAL"]("-cd clear")
local rawLine = chatHistory[1] or ""
local SHARED_PREFIX = "|cffffff00[Super Social]:|r "
expect("shared YELLOW_FONT_COLOR prefix", rawLine:sub(1, #SHARED_PREFIX) == SHARED_PREFIX, rawLine)
expect("lead tinted by GREEN_FONT_COLOR", rawLine:find("|cff19ff19Cooldown list cleared.|r", 1, true) ~= nil, rawLine)

print("\n-- /ww over a who list --")
resetRun()
setWho({ "Aaa", "Bbb", "Ccc" })
SlashCmdList["WHISPERWHO"]("hello there")
runTimers(now + 30)
expect("three whispers sent", #whisperLog == 3, "got " .. #whisperLog)
expect("run closed with a verdict", seen("Sent all 3 whispers"))

print("\n-- /ww -skip filters a row --")
resetRun()
setWho({ "Aaa", "Bbb" })
whoResults[1].classStr = "Warlock"
SlashCmdList["WHISPERWHO"]("-skip (warlock) hi")
runTimers(now + 30)
expect("one whisper sent", #whisperLog == 1, "got " .. #whisperLog)
expect("skip reported", seen("1 filtered"))

print("\n-- ambiguous name is purged, not retried --")
resetRun()
setWho({ "Aaa" })
deliveryMode = "ambiguous"
SlashCmdList["WHISPERWHO"]("hi")
runTimers(now + 60)
expect("sent once, no retries", #whisperLog == 1, "got " .. #whisperLog)
expect("reported unreachable", seen("Unreachable"))

print("\n-- /wt joins a surname the way Blizzard's menu joins it --")
resetRun()
TARGET_NAME, TARGET_SECOND, TARGET_CROSS_REALM = "Zed", "Ravencrest", false
SlashCmdList["WHISPERTARGET"]("hi there")
runTimers(now + 10)
expect("surname joined with a space", targetOf(1) == "Zed Ravencrest", "got " .. targetOf(1))

print("\n-- /wt without regionally unique names joins a realm only across realms --")
regionalNames = false
resetRun()
TARGET_NAME, TARGET_SECOND, TARGET_CROSS_REALM = "Zed", "Ravencrest", true
SlashCmdList["WHISPERTARGET"]("hi there")
runTimers(now + 10)
expect("cross-realm target keeps its realm", targetOf(1) == "Zed-Ravencrest", "got " .. targetOf(1))
resetRun()
TARGET_NAME, TARGET_SECOND, TARGET_CROSS_REALM = "Zed", "Homerealm", false
SlashCmdList["WHISPERTARGET"]("hi there")
runTimers(now + 10)
expect("same-realm target whispers the bare name", targetOf(1) == "Zed", "got " .. targetOf(1))
regionalNames = true

print("\n-- /wt with no second part --")
resetRun()
TARGET_NAME, TARGET_SECOND, TARGET_CROSS_REALM = "Yan", nil, false
SlashCmdList["WHISPERTARGET"]("hi there")
runTimers(now + 10)
expect("nil second part whispers the bare name", targetOf(1) == "Yan", "got " .. targetOf(1))
expect("nil second part is not read as hidden", not seen("Target name hidden"))

print("\n-- name keys --")
local sameCases = {
    { "Bob", "bob", true }, { "Bob", "Bob-Realm", true }, { "Bob-Realm", "Bob-Other", false },
    { "Bob Smith", "Bob-Smith", true }, { "Bob Smith", "Bob", true }, { "Bob Smith", "Bob Jones", false },
    { "Bob Smith", "Bob Smith-Realm", true }, { "Bob", "Rob", false }, { "Bob", nil, false },
}
for _, case in ipairs(sameCases) do
    expect(("%s vs %s"):format(tostring(case[1]), tostring(case[2])), ns.SameName(case[1], case[2]) == case[3])
end
expect("key folds both separators", ns.NameKey("Bob Smith") == "bob-smith" and ns.NameKey("BOB-SMITH") == "bob-smith")
expect("bare key finds full stored key", ns.FindKeyScan({ ["bob-smith"] = true }, "Bob") == "bob-smith")
expect("full key falls back to bare stored key", ns.FindKey({ bob = true }, "Bob Smith") == "bob")

print("\n-- an echo in another spelling still confirms the whisper --")
resetRun()
TARGET_NAME, TARGET_SECOND, TARGET_CROSS_REALM = "Zed", "Ravencrest", false
echoName = function(target) return (target:gsub(" ", "-")) end
SlashCmdList["WHISPERTARGET"]("spelling check")
runTimers(now + 40)
expect("/wt sent once, not resent", #whisperLog == 1, "got " .. #whisperLog)
expect("/wt never gave up", not seen("Gave up"))
resetRun()
setWho({ "Aaa Bbb" })
echoName = function() return "Aaa" end
SlashCmdList["WHISPERWHO"]("spelling check")
runTimers(now + 40)
expect("/ww sent once, not resent", #whisperLog == 1, "got " .. #whisperLog)
expect("/ww confirmed", seen("Sent 1 whisper"))

print("\n-- the group skip tells surnames apart --")
resetRun()
groupRoster = { { "Gmate", "Ddd" } }
setWho({ "Gmate Ddd", "Gmate Eee" })
SlashCmdList["WHISPERWHO"]("group check")
runTimers(now + 30)
expect("one groupmate skipped", seen("1 in your group"))
expect("the other row whispered", #whisperLog == 1 and targetOf(1) == "Gmate Eee", "got " .. targetOf(1))
groupRoster = {}

print("\n-- a hyphen block entry catches the spaced who row --")
resetRun()
SlashCmdList["SUPERSOCIAL"]("-block Old-Timer")
expect("block list created on first use", type(SuperSocialDB) == "table" and SuperSocialDB.blockedAccount["old-timer"] == "Old-Timer")
setWho({ "Old Timer" })
resetRun()
SlashCmdList["WHISPERWHO"]("hi")
runTimers(now + 30)
expect("block entry blocks", seen("1 blocked"))
SlashCmdList["SUPERSOCIAL"]("-unblock Old-Timer")

print("\n-- the run counter rewrites its own line --")
resetRun()
chatHistory = {}
-- A whisper received inside restricted content stays secret in chat history after the player leaves.
local secretLine = setmetatable({}, { __tostring = function() return "secret line" end })
secretValues[secretLine] = true
chatHistory[1] = secretLine
setWho({ "Aaa", "Bbb", "Ccc" })
local okRun = pcall(function()
    SlashCmdList["WHISPERWHO"]("counter check")
    runTimers(now + 30)
end)
expect("run survived the chat history", okRun)
local counters = 0
for _, msg in ipairs(chatHistory) do
    if type(msg) == "string" and msg:find("/3|r sent") then counters = counters + 1 end
end
expect("one counter line, rewritten in place", counters == 1, "found " .. counters)

print("\n-- /rr answers a reply and stops repeating --")
resetRun()
setWho({ "Aaa", "Bbb" })
SlashCmdList["WHISPERWHO"]("who wants in")
runTimers(now + 30)
resetRun()
fire("CHAT_MSG_WHISPER", "me!", "Aaa")
SlashCmdList["REPLYRECENT"]("")
expect("one unanswered reply listed", seen("1 unanswered"))
resetRun()
SlashCmdList["REPLYRECENT"]("invite incoming")
runTimers(now + 30)
expect("reply went out", #whisperLog == 1, "got " .. #whisperLog)
resetRun()
SlashCmdList["REPLYRECENT"]("")
expect("nothing left unanswered", seen("No unanswered replies"))

print("\n-- a cancelled reply goes back on the /rr list --")
resetRun()
fire("CHAT_MSG_WHISPER", "still here?", "Bbb")
deliveryMode = "silent"
SlashCmdList["REPLYRECENT"]("on my way")
runTimers(now + 1)
SlashCmdList["SUPERSOCIAL"]("stop")
resetRun()
SlashCmdList["REPLYRECENT"]("")
expect("reply reopened after /ss stop", seen("1 unanswered"))

print("\n-- a reply in another spelling finds its tracked recipient --")
SlashCmdList["REPLYRECENT"]("reset")
resetRun()
setWho({ "Rep Lyer" })
SlashCmdList["WHISPERWHO"]("who wants in")
runTimers(now + 30)
resetRun()
fire("CHAT_MSG_WHISPER", "me!", "Rep-Lyer")
SlashCmdList["REPLYRECENT"]("")
expect("reply tracked across spellings", seen("1 unanswered"))
SlashCmdList["REPLYRECENT"]("reset")

print("\n-- block list --")
resetRun()
SlashCmdList["SUPERSOCIAL"]("-block Aaa")
setWho({ "Aaa", "Bbb" })
resetRun()
SlashCmdList["WHISPERWHO"]("hi")
runTimers(now + 30)
expect("blocked row skipped", seen("1 blocked"))
SlashCmdList["SUPERSOCIAL"]("-unblock Aaa")

print("\n-- cooldown list --")
resetRun()
setWho({ "Ccc" })
SlashCmdList["WHISPERWHO"]("-cd 30d hi")
runTimers(now + 30)
resetRun()
SlashCmdList["WHISPERWHO"]("-cd hi")
runTimers(now + 30)
expect("cooldown row skipped", seen("1 on cooldown"))
SlashCmdList["SUPERSOCIAL"]("-cd clear")

print("\n-- flag mistakes --")
resetRun()
SlashCmdList["WHISPERWHO"]("-skip mage hi")
expect("missing brackets caught", seen("%-skip needs brackets"))
resetRun()
SlashCmdList["WHISPERWHO"]("-limit x hi")
expect("bad limit caught", seen("%-limit needs a number"))
resetRun()
SlashCmdList["REPLYRECENT"]("-who (mage) hi")
expect("-who rejected on /rr", seen("%-who doesn't apply"))

print("\n-- -who runs its own search and restores the panel --")
resetRun()
setWho({ "Ddd" })
SlashCmdList["WHISPERWHO"]("-who (mage 60) hi")
runTimers(now + 2)
expect("who search dispatched", #whisperLog == 1, "got " .. #whisperLog)
runTimers(now + 20)
expect("who frame listening again", LFGWhoListFrame:IsEventRegistered("WHO_LIST_UPDATE"))
expect("who routing restored", whoToUi == false)

print("\n-- a closed Group Finder leaves who results in chat --")
-- The Who tab keeps its shown flag when its parent closes, and its OnHide has sent results to chat.
LFGParentFrame:Show()
LFGWhoListFrame:Show()
LFGParentFrame:Hide()
whoToUi = false
resetRun()
setWho({ "Eee" })
SlashCmdList["WHISPERWHO"]("-who (mage 60) hi")
runTimers(now + 20)
expect("results still go to chat", whoToUi == false)
LFGParentFrame:Show()
whoToUi = true
resetRun()
SlashCmdList["WHISPERWHO"]("-who (mage 60) hi")
runTimers(now + 20)
expect("an open Who tab gets its results back", whoToUi == true)
LFGWhoListFrame:Hide()
LFGParentFrame:Hide()
whoToUi = false

print("\n-- an unavailable friend list reads as no results --")
friendListReady = false
resetRun()
local okEmpty = pcall(SlashCmdList["WHISPERWHO"], "hi")
expect("/ww survived an empty who count", okEmpty)
expect("/ww reported no results", seen("No /who results"))
resetRun()
local okWait = pcall(function()
    SlashCmdList["WHISPERWHO"]("-who (mage 60) hi")
    runTimers(now + 20)
end)
expect("-who survived an empty who count", okWait)
expect("-who timed out instead of whispering", seen("Nobody found") and #whisperLog == 0, "sent " .. #whisperLog)
friendListReady = true

--=== /ws =====================================================================
-- A result row as the client hands it over; a row holding your own auction names you "player".
local function resultRow(owners, total)
    local mine = false
    for _, owner in ipairs(owners) do
        if owner == "player" then mine = true end
    end
    return { owners = owners, totalNumberOfOwners = total or #owners, containsOwnerItem = mine, containsAccountItem = false }
end

local function itemKeyFor(itemID)
    return { itemID = itemID, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 }
end

-- Opening the auction house loads the load-on-demand Blizzard_AuctionHouseUI, whose window starts on its Browse list.
local function openAuctionHouse()
    if not AuctionHouseFrame then
        AuctionHouseFrameDisplayMode = { Buy = {}, ItemBuy = {}, CommoditiesBuy = {}, ItemSell = {} }
        AuctionHouseFrame = newFrame()
        function AuctionHouseFrame:GetDisplayMode() return self.displayMode end
    end
    AuctionHouseFrame.displayMode = AuctionHouseFrameDisplayMode.Buy
    AuctionHouseFrame:Show()
    fire("AUCTION_HOUSE_SHOW")
end

local function closeAuctionHouse()
    AuctionHouseFrame:Hide()
    fire("AUCTION_HOUSE_CLOSED")
end

local function showItem(itemID)
    AuctionHouseFrame.displayMode = AuctionHouseFrameDisplayMode.ItemBuy
    fire("ITEM_SEARCH_RESULTS_UPDATED", itemKeyFor(itemID))
end

local function whisperSellers(input)
    resetRun()
    SlashCmdList["WHISPERSELLERS"](input)
    runTimers(now + 30)
end

print("\n-- /ws refuses what it can't read --")
whisperSellers("hi")
expect("closed auction house refused", seen("Auction house closed"))
whisperSellers("")
expect("usage shown", seen("Usage: /ws MESSAGE"))
whisperSellers("-skip (mage) hi")
expect("term filters refused", seen("%-skip and %-only don't apply to /ws"))
whisperSellers("-who (mage) hi")
expect("-who refused", seen("%-who doesn't apply to /ws"))
openAuctionHouse()
whisperSellers("hi")
expect("Browse list without a listing refused", seen("No item listings open") and #whisperLog == 0, "sent " .. #whisperLog)

print("\n-- /ws whispers an item's sellers once each, never you --")
local hiddenOwner = setmetatable({}, { __tostring = function() return "hidden owner" end })
secretValues[hiddenOwner] = true
itemResults[2589] = {
    resultRow({ "player" }),
    resultRow({ "Sella Vend", "Other Farrealm" }),
    resultRow({ "Sella Vend" }),
    resultRow({ "Selfy Mcself" }),
    resultRow({ "", hiddenOwner }),
}
showItem(2589)
whisperSellers("still selling?")
expect("two unique sellers whispered", #whisperLog == 2, "got " .. #whisperLog)
expect("listing order kept", targetOf(1) == "Sella Vend" and targetOf(2) == "Other Farrealm", targetOf(1) .. ", " .. targetOf(2))
expect("run names the item", seen("Whispering all 2 sellers of Linen Cloth%."))
expect("echoes confirmed every whisper", seen("Sent all 2 whispers"))
expect("no unnamed note for fully named rows", not seen("unnamed by the auction house"))

print("\n-- the Browse list hides a cached listing --")
AuctionHouseFrame.displayMode = AuctionHouseFrameDisplayMode.Buy
whisperSellers("hi")
expect("back on Browse refused", seen("No item listings open") and #whisperLog == 0, "sent " .. #whisperLog)

print("\n-- commodity results replace the item listing --")
commodityResults[4306] = {
    resultRow({ "Comm One", "player", "Comm Two" }, 6),
    resultRow({ "Comm One" }),
}
AuctionHouseFrame.displayMode = AuctionHouseFrameDisplayMode.CommoditiesBuy
fire("COMMODITY_SEARCH_RESULTS_UPDATED", 4306)
whisperSellers("-limit 1 bulk price?")
expect("limit honoured", #whisperLog == 1 and targetOf(1) == "Comm One", "got " .. #whisperLog .. " to " .. targetOf(1))
expect("commodity run names its item", seen("Whispering 1 of 2 sellers of Silk Cloth"))
expect("limit skip reported", seen("1 over the limit"))
expect("unnamed sellers counted", seen("Up to 3 sellers unnamed by the auction house"))

print("\n-- Auctionator's tabs clear the display mode and still read the listing --")
AuctionHouseFrame.displayMode = nil
whisperSellers("hi ; still there?")
expect("both parts to both sellers", #whisperLog == 4, "got " .. #whisperLog)

print("\n-- the Sell tab's listing counts too --")
itemResults[5555] = { resultRow({ "Rival Seller" }) }
AuctionHouseFrame.displayMode = AuctionHouseFrameDisplayMode.ItemSell
fire("ITEM_SEARCH_RESULTS_UPDATED", itemKeyFor(5555))
whisperSellers("undercut me?")
expect("sell listing seller whispered", #whisperLog == 1 and targetOf(1) == "Rival Seller", "got " .. targetOf(1))
expect("uncached item left unnamed", seen("Whispering all 1 seller%."))

print("\n-- your own auctions or an empty listing leave nobody --")
itemResults[6666] = { resultRow({ "player" }), resultRow({ "Selfy-Mcself" }) }
showItem(6666)
whisperSellers("hi")
expect("own auctions only", seen("No other sellers") and #whisperLog == 0, "sent " .. #whisperLog)
itemResults[7777] = {}
showItem(7777)
whisperSellers("hi")
expect("no results", seen("No other sellers") and #whisperLog == 0, "sent " .. #whisperLog)

print("\n-- /ws honours cooldowns and the block list --")
showItem(2589)
whisperSellers("-cd 30d hi")
expect("cooldown run sent", #whisperLog == 2, "got " .. #whisperLog)
whisperSellers("-cd hi")
expect("sellers on cooldown skipped", seen("2 on cooldown") and #whisperLog == 0, "sent " .. #whisperLog)
SlashCmdList["SUPERSOCIAL"]("-cd clear")
SlashCmdList["SUPERSOCIAL"]("-block Sella-Vend")
whisperSellers("hi")
expect("blocked seller skipped", seen("1 blocked") and #whisperLog == 1 and targetOf(1) == "Other Farrealm", "got " .. targetOf(1))
SlashCmdList["SUPERSOCIAL"]("-unblock Sella-Vend")

print("\n-- a seller answering /ws is waiting for /rr --")
SlashCmdList["REPLYRECENT"]("reset")
whisperSellers("still selling?")
resetRun()
fire("CHAT_MSG_WHISPER", "yes", "Other Farrealm")
SlashCmdList["REPLYRECENT"]("")
expect("seller reply tracked", seen("1 unanswered"))
SlashCmdList["REPLYRECENT"]("reset")

print("\n-- /ws skips your group and anyone who just left it --")
showItem(2589)
groupRoster = { { "Sella", "Vend" } }
fire("GROUP_ROSTER_UPDATE")
whisperSellers("hi")
expect("groupmate seller skipped", seen("1 in your group") and #whisperLog == 1 and targetOf(1) == "Other Farrealm",
    "got " .. #whisperLog .. " to " .. targetOf(1))
groupRoster = {}
fire("GROUP_ROSTER_UPDATE")
whisperSellers("hi")
expect("recent groupmate seller skipped", seen("1 recently grouped") and #whisperLog == 1 and targetOf(1) == "Other Farrealm",
    "got " .. #whisperLog .. " to " .. targetOf(1))

print("\n-- /rr skips a groupmate through the same check --")
SlashCmdList["REPLYRECENT"]("reset")
whisperSellers("still selling?")
fire("CHAT_MSG_WHISPER", "yes", "Other Farrealm")
groupRoster = { { "Other", "Farrealm" } }
resetRun()
SlashCmdList["REPLYRECENT"]("thanks")
runTimers(now + 30)
expect("/rr groupmate skipped", seen("1 in your group") and #whisperLog == 0, "sent " .. #whisperLog)
groupRoster = {}
SlashCmdList["REPLYRECENT"]("reset")

print("\n-- the recent-group window runs out after 15 minutes --")
-- The stub clock only moves when a timer fires.
schedule(15 * 60 + 1, function() end)
runTimers(now + 15 * 60 + 1)
whisperSellers("hi")
expect("former groupmate whispered again", #whisperLog == 2 and not seen("recently grouped"), "got " .. #whisperLog)

print("\n-- closing the auction house forgets the listing --")
closeAuctionHouse()
whisperSellers("hi")
expect("closed after a visit refused", seen("Auction house closed") and #whisperLog == 0, "sent " .. #whisperLog)
openAuctionHouse()
AuctionHouseFrame.displayMode = AuctionHouseFrameDisplayMode.ItemBuy
whisperSellers("hi")
expect("new visit starts without a listing", seen("No item listings open") and #whisperLog == 0, "sent " .. #whisperLog)
closeAuctionHouse()

print("\n-- the /ss panel builds on ButtonFrameTemplate --")
resetRun()
SlashCmdList["SUPERSOCIAL"]("")
local panel = _G.SuperSocialFrame
expect("panel created", panel ~= nil)
expect("panel shown", panel and panel:IsShown())
expect("registered for escape", UISpecialFrames[1] == "SuperSocialFrame")
expect("title without version", panel and panel._title == "Super Social", "got " .. tostring(panel and panel._title))
expect("portrait is the toc icon", panel and panel._portrait == 134149)
expect("strata HIGH", panel and panel._strata == "HIGH")
expect("button bar hidden", panel and panel._buttonBarHidden == true)
local scrollRight = scrollFrames[1] and scrollFrames[1]._points.BOTTOMRIGHT
expect("scroll gutter fits the 8 px bar at +6 plus the inset pad", scrollRight and scrollRight[1] == -22,
    "got " .. tostring(scrollRight and scrollRight[1]))
local panelMentionsWs = false
for _, f in ipairs(frames) do
    if type(f._text) == "string" and f._text:find("/ws", 1, true) then panelMentionsWs = true end
end
expect("panel lists /ws", panelMentionsWs)
SlashCmdList["SUPERSOCIAL"]("")
expect("second /ss closes it", panel and not panel:IsShown())

print("\n-- rate and quiet subcommands --")
resetRun()
SlashCmdList["SUPERSOCIAL"]("rate")
expect("rate reported", seen("Send rate"))
resetRun()
SlashCmdList["SUPERSOCIAL"]("quiet off")
expect("quiet toggled", seen("Quiet mode off"))
SlashCmdList["SUPERSOCIAL"]("quiet on")

print("\n-- secret payloads are ignored, not parsed --")
resetRun()
local secretText = setmetatable({}, { __tostring = function() return "secret" end })
secretValues[secretText] = true
local okSystem = pcall(fire, "CHAT_MSG_SYSTEM", secretText)
local okEcho = pcall(fire, "CHAT_MSG_WHISPER_INFORM", secretText, secretText)
local okWhisper = pcall(fire, "CHAT_MSG_WHISPER", secretText, secretText)
expect("secret system message survived", okSystem)
expect("secret echo survived", okEcho)
expect("secret incoming whisper survived", okWhisper)

print("\n-- a hidden groupmate is left out, not an error --")
resetRun()
groupRoster = { { secretText, nil } }
setWho({ "Aaa Zzz" })
local okHidden = pcall(function()
    SlashCmdList["WHISPERWHO"]("hi")
    runTimers(now + 30)
end)
expect("hidden groupmate survived", okHidden)
expect("run still went out", #whisperLog == 1, "got " .. #whisperLog)
groupRoster = {}

print("\n-- commands refuse under a lockdown --")
resetRun()
restrictionActive = true
setWho({ "Aaa" })
SlashCmdList["WHISPERWHO"]("hi")
expect("/ww refused", seen("Chat restricted here"))
resetRun()
SlashCmdList["WHISPERTARGET"]("hi")
expect("/wt refused", seen("Chat restricted here"))
resetRun()
SlashCmdList["WHISPERSELLERS"]("hi")
expect("/ws refused", seen("Chat restricted here"))
restrictionActive = false

print("\n-- a run walking into a lockdown stops at once --")
resetRun()
setWho({ "Aaa", "Bbb", "Ccc" })
deliveryMode = "silent"
SlashCmdList["WHISPERWHO"]("hi")
runTimers(now + 0.1)
restrictionActive = true
fire("ADDON_RESTRICTION_STATE_CHANGED", Enum.AddOnRestrictionType.Map, Enum.AddOnRestrictionState.Activating)
runTimers(now + 0.01)
expect("run stopped on the event, not the sweep", seen("Chat turned restricted mid%-run"))
local sentBefore = #whisperLog
runTimers(now + 60)
expect("nothing resent afterwards", #whisperLog == sentBefore, "went from " .. sentBefore .. " to " .. #whisperLog)
restrictionActive = false

print("\n-- lifting the lockdown does not stop an unrelated run --")
resetRun()
setWho({ "Aaa" })
SlashCmdList["WHISPERWHO"]("hi")
runTimers(now + 0.1)
fire("ADDON_RESTRICTION_STATE_CHANGED", Enum.AddOnRestrictionType.Map, Enum.AddOnRestrictionState.Inactive)
runTimers(now + 30)
expect("deactivation left the run alone", not seen("Chat turned restricted mid%-run"))

print("")
if failures == 0 then
    print(("== %s secrets: all checks passed =="):format(SECRETS))
else
    print(("== %s secrets: %d FAILURES =="):format(SECRETS, failures))
    os.exit(1)
end
