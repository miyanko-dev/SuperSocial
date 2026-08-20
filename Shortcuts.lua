local _, ns = ...

-- Modifier clicks on chat names, unit frames and friends panel lists: Ctrl whispers, Cmd/Alt invites, Opt/Win adds friend.

local isMac = IsMacClient and IsMacClient()

-- Help.lua labels its shortcut rows from these, so the panel names the keys of the client it runs on.
ns.ModifierLabels = {
    whisper = "Ctrl-click",
    invite = isMac and "Cmd-click" or "Alt-click",
    friend = isMac and "Option-click" or "Win-click",
}

local function inviteMod()
    if isMac then return IsMetaKeyDown() end
    return IsAltKeyDown()
end

local function friendMod()
    if isMac then return IsAltKeyDown() end
    return IsMetaKeyDown()
end

-- Resolve held modifiers to one action so chat and unit frames share behavior.
local function pickAction()
    if IsControlKeyDown() then return "whisper" end
    if inviteMod() then return "invite" end
    if friendMod() then return "friend" end
end

-- Unit frames preset the edit box, because a secure click cannot open a tab for us.
local function runAction(action, name, chatFrame)
    if action == "whisper" then
        ChatFrameUtil.SendTell(name, chatFrame)
    elseif action == "invite" then
        C_PartyInfo.InviteUnit(name)
    else
        C_FriendList.AddFriend(name)
    end
end

-- Find the player's dedicated whisper window so repeat clicks never stack duplicate tabs.
local function findWhisperTab(name)
    local target = strlower(name)
    for _, frameName in pairs(CHAT_FRAMES) do
        local frame = _G[frameName]
        if frame and frame.isTemporary and frame.inUse and frame.chatType == "WHISPER"
            and frame.chatTarget and strlower(frame.chatTarget) == target then
            return frame
        end
    end
end

-- Open without a source frame because migrating whispers out of it kills its hyperlinks
local function openWhisperTab(name)
    local frame = findWhisperTab(name)
        or FCF_OpenTemporaryWindow("WHISPER", name, nil, true)
    if not frame then return end

    if frame.isDocked then FCF_SelectDockFrame(frame) end
    FCF_FadeInChatFrame(frame)

    -- The tab's own edit box is already set to whisper this target, so typing works at once.
    ChatFrameUtil.ActivateChat(frame.editBox)
end

-- Set when a modifier click handled a name, so the default whisper that
-- SetItemRef opens on the same click gets undone before it draws.
local pendingClick

local function onChatClick(link, button)
    if button ~= "LeftButton" then return end
    local name = link:match("^player:([^:]+)")
    if not name or name == "" then return end

    local action = pickAction()
    if not action then return end

    pendingClick = { action = action, name = name }
end

EventRegistry:RegisterCallback("ChatFrame.OnHyperlinkClick", function(_, _, link, _, button)
    onChatClick(link, button)
end, "SuperSocial")

-- Drop the text OpenChat staged, because Deactivate leaves it pending in classic
-- chat style and it would stamp the next edit box the user opens.
local function closeDefaultWhisperBox()
    local editBox = ChatFrameUtil.GetActiveWindow()
    if not editBox then return end

    editBox.text = ""
    editBox.setText = 0
    ChatFrameUtil.DeactivateChat(editBox)
end

-- OnHyperlinkClick runs our callback first, then SetItemRef opens the default
-- whisper box; this post-hook runs the same frame right after, before it draws.
hooksecurefunc("SetItemRef", function()
    local click = pendingClick
    if not click then return end
    pendingClick = nil

    closeDefaultWhisperBox()

    if click.action == "whisper" then
        openWhisperTab(click.name)
    else
        runAction(click.action, click.name)
    end
end)

-- Mirror the chat shortcuts on secure unit buttons via taint-free post-hooks.
local hookedFrames = {}

local function onUnitFrameClick(frame, button)
    if button ~= "LeftButton" then return end

    local action = pickAction()
    if not action then return end

    local unit = frame.displayedUnit or (frame.GetUnit and frame:GetUnit()) or frame.unit
    if not unit or not UnitIsPlayer(unit) or UnitIsUnit(unit, "player") then return end

    local name = GetUnitName(unit, true)
    if name then runAction(action, name) end
end

local function hookUnitFrame(frame)
    if not frame or hookedFrames[frame] then return end
    hookedFrames[frame] = true
    frame:HookScript("OnClick", onUnitFrameClick)
end

hookUnitFrame(TargetFrame)
hookUnitFrame(TargetFrame and TargetFrame.totFrame)

-- Party member frames are pooled, so re-hook whenever the pool re-initializes.
local function hookPartyFrames()
    for frame in PartyFrame.PartyMemberFramePool:EnumerateActive() do
        hookUnitFrame(frame)
    end
end

if PartyFrame and PartyFrame.PartyMemberFramePool then
    hookPartyFrames()
    hooksecurefunc(PartyFrame, "InitializePartyMemberFrames", hookPartyFrames)
end

-- Raid frames and raid-style party frames all pass through this setup function.
hooksecurefunc("CompactUnitFrame_SetUpFrame", hookUnitFrame)

-- BNet friends need account APIs, because name-based actions only cover WoW friends.
local function runBNetAction(action, id)
    local _, accountName, _, _, _, gameAccountID = BNGetFriendInfo(id)
    if action == "whisper" and accountName then
        ChatFrameUtil.SendBNetTell(accountName)
    elseif action == "invite" and gameAccountID then
        FriendsFrame_InviteOrRequestToJoin(select(20, BNGetGameAccountInfo(gameAccountID)), gameAccountID)
    end
end

local function onFriendClick(frame, button)
    if button ~= "LeftButton" then return end

    local action = pickAction()
    if not action then return end

    if frame.buttonType == FRIENDS_BUTTON_TYPE_WOW then
        local info = C_FriendList.GetFriendInfoByIndex(frame.id)
        if info and info.name then runAction(action, info.name) end
    elseif frame.buttonType == FRIENDS_BUTTON_TYPE_BNET then
        runBNetAction(action, frame.id)
    end
end

local function onWhoClick(frame, button)
    if button ~= "LeftButton" then return end

    local action = pickAction()
    if not action then return end

    local info = C_FriendList.GetWhoInfo(frame.whoIndex)
    if info and info.fullName then runAction(action, info.fullName) end
end

local function onGuildClick(frame, button)
    if button ~= "LeftButton" then return end

    local action = pickAction()
    if not action then return end

    local name = GetGuildRosterInfo(frame.guildIndex)
    if name then runAction(action, name) end
end

-- Friends and who buttons call these globals from inline XML, so function hooks fire.
hooksecurefunc("FriendsFrameFriendButton_OnClick", onFriendClick)
hooksecurefunc("FriendsFrameWhoButton_OnClick", onWhoClick)

-- Guild buttons bind their handler by value in XML, so hook each static button instead.
for i = 1, GUILDMEMBERS_TO_DISPLAY do
    _G["GuildFrameButton" .. i]:HookScript("OnClick", onGuildClick)
    _G["GuildFrameGuildStatusButton" .. i]:HookScript("OnClick", onGuildClick)
end

local function onLFGEntryClick(frame, button)
    if button ~= "LeftButton" or frame.isDelisted or frame.hasSelf then return end

    local action = pickAction()
    if not action then return end

    local info = C_LFGList.GetSearchResultInfo(frame.resultID)
    if info and info.leaderName then runAction(action, info.leaderName) end
end

-- LFG entries bind their handler by value at creation, so hook the global before any exist.
EventUtil.ContinueOnAddOnLoaded("Blizzard_GroupFinder_VanillaStyle", function()
    hooksecurefunc("LFGBrowseSearchEntry_OnClick", onLFGEntryClick)
end)
