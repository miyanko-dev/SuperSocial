-- Stub WoW client for SuperSocial. Loads the toc file list in order and drives the slash commands
-- in a 1.15.9-shaped environment and a 1.60.1-shaped one. Proves load order, API surface and control
-- flow only; it is not a client and proves nothing about in-game behaviour.

local ADDON_DIR = arg[1] or "."
local SHAPE = arg[2] or "vanilla" -- vanilla | camelot
-- How the secret predicates treat a secret from tainted code, which no source settles: strict raises, lenient answers.
local SECRETS = arg[3] or "strict" -- strict | lenient

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
    function f:UnregisterAllEvents() self._events = {} end
    function f:IsEventRegistered(e) return self._events[e] == true end
    function f:SetScript(name, fn)
        self._scripts[name] = fn
        if name == "OnEvent" then self._onEvent = fn end
    end
    function f:GetScript(name) return self._scripts[name] end
    function f:Show() self._shown = true end
    function f:Hide() self._shown = false end
    function f:IsShown() return self._shown end
    function f:IsVisible() return self._shown end
    function f:SetPoint() end
    function f:SetSize() end
    function f:SetWidth() end
    function f:SetHeight() end
    function f:GetWidth() return 420 end
    function f:GetHeight() return 100 end
    function f:SetFrameStrata() end
    function f:SetToplevel() end
    function f:SetClampedToScreen() end
    function f:SetMovable() end
    function f:EnableMouse() end
    function f:RegisterForDrag() end
    function f:StartMoving() end
    function f:StopMovingOrSizing() end
    function f:SetScrollChild() end
    function f:SetJustifyH() end
    function f:SetSpacing() end
    function f:SetText(text) self._text = text end
    function f:GetStringHeight() return 12 end
    function f:GetStringWidth() return 80 end
    function f:SetTexture() end
    function f:SetTexCoord() end
    function f:SetBackdrop() end
    function f:SetBackdropColor() end
    function f:SetBackdropBorderColor() end
    function f:SetFocus() end
    function f:Insert() end
    function f:GetNumLetters() return 0 end
    function f:GetMaxLetters() return 255 end
    function f:CreateTexture() return newFrame() end
    function f:CreateFontString() return newFrame() end
    frames[#frames + 1] = f
    return f
end

--=== template-provided children ============================================
-- BasicFrameTemplateWithInset hands the frame a TitleText, a CloseButton and its InsetBg well, and
-- ScrollFrameTemplate builds a ScrollBar in its OnLoad; all are verified present on classic_era and
-- forever, so the stub supplies them too.
local KNOWN_TEMPLATES = {
    BasicFrameTemplateWithInset = function(f) f.TitleText = newFrame(); f.CloseButton = newFrame(); f.InsetBg = newFrame() end,
    InsetFrameTemplate = function(f) f.NineSlice = newFrame() end,
    ScrollFrameTemplate = function(f) f.ScrollBar = newFrame() end,
    UIPanelCloseButton = function() end,
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
NORMAL_FONT_COLOR = { WrapTextInColorCode = function(_, text) return "|cffffd100" .. text .. "|r" end }

function GetTime() return now end
function time() return wallclock end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function tinsert(t, v) t[#t + 1] = v end
function IsModifiedClick() return false end

C_Timer = {
    After = function(delay, fn) schedule(delay, fn) end,
    NewTimer = function(delay, fn)
        local t = schedule(delay, fn)
        return { Cancel = function() t.cancelled = true end }
    end,
}

EventUtil = { ContinueOnAddOnLoaded = function(_, fn) schedule(0, fn) end }

--=== group ==================================================================
-- Units answer (name, second): the second part is a realm on vanilla and a surname on camelot.
-- A same-realm Era unit comes back with a nil realm, never an empty string.
local groupRoster = {}
function IsInGroup() return #groupRoster > 0 end
function IsInRaid() return false end
function GetNumGroupMembers() return #groupRoster end
local function unitParts(unit)
    if unit == "player" then return "Selfy", SHAPE == "camelot" and "Mcself" or nil end
    if unit == "target" then return TARGET_NAME, TARGET_SECOND end
    local index = unit:match("^party(%d)$")
    local member = index and groupRoster[tonumber(index)]
    if member then return member[1], member[2] end
    return nil
end
UnitName = unitParts
UnitNameUnmodified = unitParts
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

-- Only the namespaced call: the bare SendChatMessage global needs the loadDeprecationFallbacks CVar on both builds.
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

--=== who list ===============================================================
local whoResults = {}
local whoToUi = false
C_FriendList = {
    GetNumWhoResults = function() return #whoResults, #whoResults end,
    GetWhoInfo = function(i) return whoResults[i] end,
    SetWhoToUi = function(v) whoToUi = v end,
    SendWho = function()
        schedule(0.5, function() fire("WHO_LIST_UPDATE") end)
    end,
}

--=== slash commands =========================================================
SlashCmdList = {}

--=== per-shape client surface ==============================================
local restrictionActive = false
local secretValues = {}

local auctions = {}

if SHAPE == "vanilla" then
    -- 1.15.9: the machinery exists, no restriction ever activates and nothing is ever secret. The
    -- classic auction house still lists sellers.
    ERR_CHAT_WRONG_FACTION = "You can only whisper to members of your alliance."
    ERR_CHAT_RESTRICTED = "Free Trial accounts cannot send unlimited tells."
    FriendsFrame = newFrame()
    FriendsFrame:RegisterEvent("WHO_LIST_UPDATE")
    WhoFrame = newFrame()
    ChatFrame_AddMessageEventFilter = function(event, fn) chatFilters[event] = fn end
    AuctionFrame = newFrame()
    function GetNumAuctionItems() return #auctions, #auctions end
    function GetAuctionItemInfo(_, i)
        local row = auctions[i]
        return nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, row.owner, row.full
    end
else
    -- 1.60.1: no WhoFrame, the Who tab is the load-on-demand LFGWhoListFrame, ChatFrameUtil is the
    -- filter API, and chat payloads go secret under a lockdown. ERR_CHAT_WRONG_FACTION is gone, the
    -- modern auction house exposes no sellers, and regionally unique names
    -- join a surname with " ".
    FriendsFrame = newFrame()
    LFGWhoListFrame = newFrame()
    LFGWhoListFrame:RegisterEvent("WHO_LIST_UPDATE")
    ChatFrameUtil = {
        AddMessageEventFilter = function(event, fn) chatFilters[event] = fn end,
    }
    function RegionalUniqueNamesEnabled() return true end
    Constants = { CharacterNameSeparatorConsts = { CHARACTERNAME_REALMNAME_SEPARATOR = "-", CHARACTERNAME_SURNAME_SEPARATOR = " " } }
end

-- Both builds declare the argument Nilable = false, so nil raises. Neither build is allowed to answer for a secret in strict mode.
local function secretPredicate(answerSecret)
    return function(value)
        assert(value ~= nil, "bad argument #1: value expected")
        if secretValues[value] then
            if SECRETS == "strict" then error("Secret values are only allowed during untainted execution for this argument.") end
            return answerSecret
        end
        return not answerSecret
    end
end
issecretvalue = secretPredicate(true)
canaccessvalue = secretPredicate(false)

Enum = {
    AddOnRestrictionType = { Combat = 0, Encounter = 1, ChallengeMode = 2, PvPMatch = 3, Map = 4, Chat = 5 },
    AddOnRestrictionState = { Inactive = 0, Activating = 1, Active = 2 },
}

C_RestrictedActions = {
    IsAddOnRestrictionActive = function(t) return restrictionActive and t == Enum.AddOnRestrictionType.Map end,
}

-- The addon asks this rather than mapping restriction types itself; present on both real builds.
C_ChatInfo = {
    InChatMessagingLockdown = function() return restrictionActive end,
    SendChatMessage = sendChatMessage,
}

--=== load the addon in toc order ===========================================
-- Saved variables from before name keys, so the one-time re-key has something to fold.
SuperSocialDB = {
    cooldownFormat = 2,
    blockedAccount = { ["old-timer"] = "Old-Timer" },
}

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
print(("== %s shape, %s secrets: loaded %d files =="):format(SHAPE, SECRETS, #order))

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

print("\n-- /wt with a second name part: Era realm across realms, Forever surname --")
resetRun()
TARGET_NAME, TARGET_SECOND, TARGET_CROSS_REALM = "Zed", "Ravencrest", true
SlashCmdList["WHISPERTARGET"]("hi there")
runTimers(now + 10)
local expectedTarget = SHAPE == "camelot" and "Zed Ravencrest" or "Zed-Ravencrest"
expect("second part joined the way Blizzard's menu joins it", whisperLog[1] and whisperLog[1].target == expectedTarget,
    "got " .. tostring(whisperLog[1] and whisperLog[1].target))

print("\n-- /wt with a same-realm target that still reports its realm --")
resetRun()
TARGET_NAME, TARGET_SECOND, TARGET_CROSS_REALM = "Zed", "Homerealm", false
SlashCmdList["WHISPERTARGET"]("hi there")
runTimers(now + 10)
expectedTarget = SHAPE == "camelot" and "Zed Homerealm" or "Zed"
expect("same-realm Era target whispers the bare name", whisperLog[1] and whisperLog[1].target == expectedTarget,
    "got " .. tostring(whisperLog[1] and whisperLog[1].target))

print("\n-- /wt with no second part --")
resetRun()
TARGET_NAME, TARGET_SECOND, TARGET_CROSS_REALM = "Yan", nil, false
SlashCmdList["WHISPERTARGET"]("hi there")
runTimers(now + 10)
expect("nil second part whispers the bare name", whisperLog[1] and whisperLog[1].target == "Yan",
    "got " .. tostring(whisperLog[1] and whisperLog[1].target))
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
TARGET_NAME, TARGET_SECOND, TARGET_CROSS_REALM = "Zed", "Ravencrest", true
echoName = function(target) return (target:gsub(" ", "-")) end
SlashCmdList["WHISPERTARGET"]("spelling check")
runTimers(now + 40)
expect("/wt sent once, not resent", #whisperLog == 1, "got " .. #whisperLog)
expect("/wt never gave up", not seen("Gave up"))
resetRun()
setWho({ SHAPE == "camelot" and "Aaa Bbb" or "Aaa" })
echoName = function(target)
    if SHAPE == "camelot" then return "Aaa" end
    return target .. "-Homerealm"
end
SlashCmdList["WHISPERWHO"]("spelling check")
runTimers(now + 40)
expect("/ww sent once, not resent", #whisperLog == 1, "got " .. #whisperLog)
expect("/ww confirmed", seen("Sent 1 whisper"))

print("\n-- the group skip tells surnames apart --")
resetRun()
groupRoster = { { "Gmate", SHAPE == "camelot" and "Ddd" or nil } }
setWho(SHAPE == "camelot" and { "Gmate Ddd", "Gmate Eee" } or { "Gmate", "Other" })
SlashCmdList["WHISPERWHO"]("group check")
runTimers(now + 30)
expect("one groupmate skipped", seen("1 in your group"))
expect("the other row whispered", #whisperLog == 1 and whisperLog[1].target == (SHAPE == "camelot" and "Gmate Eee" or "Other"),
    "got " .. tostring(whisperLog[1] and whisperLog[1].target))
groupRoster = {}

print("\n-- pre-name-key saved variables are re-keyed once --")
resetRun()
expect("re-key recorded", SuperSocialDB.nameKeyFormat == 2)
setWho({ SHAPE == "camelot" and "Old Timer" or "Old-Timer" })
SlashCmdList["WHISPERWHO"]("hi")
runTimers(now + 30)
expect("old block entry still blocks", seen("1 blocked"))

print("\n-- the run counter rewrites its own line --")
resetRun()
chatHistory = {}
if SHAPE == "camelot" then
    -- A whisper received inside restricted content stays secret in chat history after the player leaves.
    local secretLine = setmetatable({}, { __tostring = function() return "secret line" end })
    secretValues[secretLine] = true
    chatHistory[1] = secretLine
end
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
setWho({ SHAPE == "camelot" and "Rep Lyer" or "Replyer" })
SlashCmdList["WHISPERWHO"]("who wants in")
runTimers(now + 30)
resetRun()
fire("CHAT_MSG_WHISPER", "me!", SHAPE == "camelot" and "Rep-Lyer" or "Replyer-Homerealm")
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
local whoFrame = SHAPE == "camelot" and LFGWhoListFrame or FriendsFrame
expect("who frame listening again", whoFrame:IsEventRegistered("WHO_LIST_UPDATE"))
expect("who routing restored", whoToUi == false)

print("\n-- help panel builds --")
resetRun()
SlashCmdList["SUPERSOCIAL"]("")
expect("panel created", _G.SuperSocialHelpFrame ~= nil)
expect("panel shown", _G.SuperSocialHelpFrame and _G.SuperSocialHelpFrame:IsShown())
expect("registered for escape", UISpecialFrames[1] == "SuperSocialHelpFrame")
local panelMentionsWs = false
for _, f in ipairs(frames) do
    if type(f._text) == "string" and f._text:find("/ws", 1, true) then panelMentionsWs = true end
end
expect("/ws listed only where it exists", panelMentionsWs == (SHAPE == "vanilla"))
SlashCmdList["SUPERSOCIAL"]("")

print("\n-- /ws exists only with the classic auction house --")
resetRun()
if SHAPE == "vanilla" then
    auctions = {
        { owner = "Sella" }, { owner = "Sella" }, { owner = "Other", full = "Other-Farrealm" }, { owner = "Selfy" },
    }
    AuctionFrame:Hide()
    SlashCmdList["WHISPERSELLERS"]("hi")
    expect("closed auction house refused", seen("Auction house closed"))
    resetRun()
    SlashCmdList["WHISPERSELLERS"]("-skip (mage) hi")
    expect("term filters refused", seen("%-skip and %-only don't apply"))
    resetRun()
    AuctionFrame:Show()
    SlashCmdList["WHISPERSELLERS"]("still selling?")
    runTimers(now + 30)
    expect("each seller once, never yourself", #whisperLog == 2, "got " .. #whisperLog)
    expect("seller realm kept", whisperLog[2] and whisperLog[2].target == "Other-Farrealm")
    expect("run reported sellers", seen("all 2 sellers"))
    AuctionFrame:Hide()
else
    expect("/ws not registered", SlashCmdList["WHISPERSELLERS"] == nil and SLASH_WHISPERSELLERS1 == nil)
end

print("\n-- rate and quiet subcommands --")
resetRun()
SlashCmdList["SUPERSOCIAL"]("rate")
expect("rate reported", seen("Send rate"))
resetRun()
SlashCmdList["SUPERSOCIAL"]("quiet off")
expect("quiet toggled", seen("Quiet mode off"))
SlashCmdList["SUPERSOCIAL"]("quiet on")

if SHAPE == "camelot" then
    print("\n-- 1.60 only: secret payloads are ignored, not parsed --")
    resetRun()
    local secretText = setmetatable({}, { __tostring = function() return "secret" end })
    secretValues[secretText] = true
    local okSystem = pcall(fire, "CHAT_MSG_SYSTEM", secretText)
    local okEcho = pcall(fire, "CHAT_MSG_WHISPER_INFORM", secretText, secretText)
    local okWhisper = pcall(fire, "CHAT_MSG_WHISPER", secretText, secretText)
    expect("secret system message survived", okSystem)
    expect("secret echo survived", okEcho)
    expect("secret incoming whisper survived", okWhisper)

    print("\n-- 1.60 only: a hidden groupmate is left out, not an error --")
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

    print("\n-- 1.60 only: commands refuse under a lockdown --")
    resetRun()
    restrictionActive = true
    setWho({ "Aaa" })
    SlashCmdList["WHISPERWHO"]("hi")
    expect("/ww refused", seen("Chat restricted here"))
    resetRun()
    SlashCmdList["WHISPERTARGET"]("hi")
    expect("/wt refused", seen("Chat restricted here"))
    restrictionActive = false

    print("\n-- 1.60 only: a run walking into a lockdown stops at once --")
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

    print("\n-- 1.60 only: lifting the lockdown does not stop an unrelated run --")
    resetRun()
    setWho({ "Aaa" })
    SlashCmdList["WHISPERWHO"]("hi")
    runTimers(now + 0.1)
    fire("ADDON_RESTRICTION_STATE_CHANGED", Enum.AddOnRestrictionType.Map, Enum.AddOnRestrictionState.Inactive)
    runTimers(now + 30)
    expect("deactivation left the run alone", not seen("Chat turned restricted mid%-run"))
end

print("")
if failures == 0 then
    print(("== %s shape, %s secrets: all checks passed =="):format(SHAPE, SECRETS))
else
    print(("== %s shape, %s secrets: %d FAILURES =="):format(SHAPE, SECRETS, failures))
    os.exit(1)
end
