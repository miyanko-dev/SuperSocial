local ADDON_NAME = "GetInTouch"
local YELLOW = "|cffffff00"
local RESET = "|r"
local STATUS_PREFIX = YELLOW .. "[GetInTouch]:" .. RESET .. " "

local RAID_ICONS = {
    star = 1, circle = 2, diamond = 3, triangle = 4,
    moon = 5, square = 6, cross = 7, skull = 8,
}

local DEDUP_TTL = 10
local DEDUP_MAX = 20

local panel
local scanWindowFrame
local channelCheckboxes = {}
local outputCheckboxes = {}
local keywordEditBox
local channelListChildren = {}
local outputListChildren = {}

local scanning = false
local scanFrame = CreateFrame("Frame")
local parsedGroups = {}
local selectedChannelNames = {}
local selectedOutputs = {}
local recentMatches = {}

local function status(msg)
    DEFAULT_CHAT_FRAME:AddMessage(STATUS_PREFIX .. msg)
end

local function characterKey()
    return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
end

local function ensureDB()
    GetInTouchDB = GetInTouchDB or {}
    GetInTouchDB.chatScan = GetInTouchDB.chatScan or {}
    local key = characterKey()
    GetInTouchDB.chatScan[key] = GetInTouchDB.chatScan[key] or {
        inputChannels = {},
        outputs = { self = true, scanWindow = false },
        keywordText = "",
        scanEnabled = false,
    }
    local store = GetInTouchDB.chatScan[key]
    store.inputChannels = store.inputChannels or {}
    store.outputs = store.outputs or { self = true, scanWindow = false }
    store.keywordText = store.keywordText or ""
    if store.scanEnabled == nil then store.scanEnabled = false end
    return store
end

local function renderIcons(text)
    return (text:gsub("{(.-)}", function(symbol)
        local index = RAID_ICONS[strlower(symbol)]
        if index then
            return "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_" .. index .. ":0|t"
        end
        return "{" .. symbol .. "}"
    end))
end

local function parseKeywordText(text)
    local groups = {}
    if not text or text == "" then return groups end
    for rawGroup in string.gmatch(text, "[^,]+") do
        local group = rawGroup:match("^%s*(.-)%s*$")
        if group and group ~= "" then
            local terms = {}
            for rawTerm in string.gmatch(group, "[^+]+") do
                local term = rawTerm:match("^%s*(.-)%s*$")
                if term and term ~= "" then
                    terms[#terms + 1] = strlower(term)
                end
            end
            if #terms > 0 then
                groups[#groups + 1] = terms
            end
        end
    end
    return groups
end

local function messageMatches(text)
    if #parsedGroups == 0 then return false end
    local lower = strlower(text)
    for _, terms in ipairs(parsedGroups) do
        local all = true
        for _, term in ipairs(terms) do
            if not strfind(lower, term, 1, true) then
                all = false
                break
            end
        end
        if all then return true end
    end
    return false
end

local function isDuplicate(sender, msg)
    local now = GetTime()
    local key = (sender or "?") .. "\031" .. msg
    for i = #recentMatches, 1, -1 do
        local entry = recentMatches[i]
        if now - entry.t > DEDUP_TTL then
            table.remove(recentMatches, i)
        elseif entry.k == key then
            return true
        end
    end
    recentMatches[#recentMatches + 1] = { k = key, t = now }
    while #recentMatches > DEDUP_MAX do
        table.remove(recentMatches, 1)
    end
    return false
end

local function ensureScanWindow()
    if scanWindowFrame then return scanWindowFrame end
    for i = 1, NUM_CHAT_WINDOWS or 10 do
        local name = GetChatWindowInfo and GetChatWindowInfo(i)
        if name == "ChatScan" then
            scanWindowFrame = _G["ChatFrame" .. i]
            return scanWindowFrame
        end
    end
    if FCF_OpenNewWindow then
        FCF_OpenNewWindow("ChatScan")
        for i = 1, NUM_CHAT_WINDOWS or 10 do
            local name = GetChatWindowInfo and GetChatWindowInfo(i)
            if name == "ChatScan" then
                scanWindowFrame = _G["ChatFrame" .. i]
                return scanWindowFrame
            end
        end
    end
    return nil
end

local function dispatchMatch(msg, sender)
    local rendered = renderIcons(msg)
    local line = "|Hplayer:" .. sender .. "|h" .. YELLOW .. "[" .. sender .. "]:" .. RESET .. "|h " .. rendered

    if selectedOutputs.self then
        DEFAULT_CHAT_FRAME:AddMessage(line)
    end
    if selectedOutputs.scanWindow then
        local frame = ensureScanWindow()
        if frame then
            frame:AddMessage(line)
        elseif not selectedOutputs.self then
            DEFAULT_CHAT_FRAME:AddMessage(line)
        end
    end

    PlaySound(3175, "Master", true)
end

scanFrame:SetScript("OnEvent", function(_, event, ...)
    if event ~= "CHAT_MSG_CHANNEL" then return end
    local msg, sender, _, _, _, _, _, _, channelName = ...
    if not msg or msg == "" then return end
    local nameKey = channelName and strlower(channelName) or nil
    if not nameKey or not selectedChannelNames[nameKey] then return end
    if not messageMatches(msg) then return end
    if isDuplicate(sender, msg) then return end
    dispatchMatch(msg, sender or UNKNOWN or "?")
end)

local function applySettingsToRuntime(store)
    parsedGroups = parseKeywordText(store.keywordText)
    selectedChannelNames = {}
    for name, on in pairs(store.inputChannels) do
        if on then selectedChannelNames[strlower(name)] = true end
    end
    selectedOutputs = {}
    for k, v in pairs(store.outputs) do
        selectedOutputs[k] = v and true or false
    end
end

local function countTable(t)
    local n = 0
    for _, v in pairs(t) do if v then n = n + 1 end end
    return n
end

local function startScan()
    local store = ensureDB()
    applySettingsToRuntime(store)

    if not store.keywordText or store.keywordText:match("^%s*$") then
        status("No keywords entered. Open /chatscan to configure.")
        return false
    end
    if #parsedGroups == 0 then
        status("No keywords entered. Open /chatscan to configure.")
        return false
    end
    if countTable(selectedChannelNames) == 0 then
        status("No input channels selected. Open /chatscan to configure.")
        return false
    end
    if countTable(selectedOutputs) == 0 then
        status("No output destinations selected. Open /chatscan to configure.")
        return false
    end

    if not scanFrame:IsEventRegistered("CHAT_MSG_CHANNEL") then
        scanFrame:RegisterEvent("CHAT_MSG_CHANNEL")
    end
    scanning = true
    store.scanEnabled = true
    status(string.format("Scanning %d channel(s) for %d keyword group(s).",
        countTable(selectedChannelNames), #parsedGroups))
    return true
end

local function stopScan()
    if scanFrame:IsEventRegistered("CHAT_MSG_CHANNEL") then
        scanFrame:UnregisterEvent("CHAT_MSG_CHANNEL")
    end
    if scanning then
        scanning = false
        status("Scan stopped.")
    end
    local store = GetInTouchDB and GetInTouchDB.chatScan and GetInTouchDB.chatScan[characterKey()]
    if store then store.scanEnabled = false end
end

local function clearChildren(list)
    for _, child in ipairs(list) do
        child:Hide()
        child:SetParent(nil)
    end
    wipe(list)
end

local function rebuildChannelList(parent, anchorTop, store)
    clearChildren(channelListChildren)
    wipe(channelCheckboxes)

    local list = { GetChannelList() }
    local entries = {}
    for i = 1, #list, 3 do
        local id, name = list[i], list[i + 1]
        if name and name ~= "" then
            entries[#entries + 1] = { id = id, name = name }
        end
    end

    local anchor = anchorTop
    local yOffset = -4
    if #entries == 0 then
        local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        fs:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 4, yOffset)
        fs:SetText("(not in any channels)")
        channelListChildren[#channelListChildren + 1] = fs
        return fs, 16
    end

    local lastFrame = anchor
    local totalHeight = 0
    for _, entry in ipairs(entries) do
        local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
        cb:SetSize(20, 20)
        cb:SetPoint("TOPLEFT", lastFrame, "BOTTOMLEFT", lastFrame == anchor and 0 or 0, yOffset)
        local label = entry.name
        if cb.Text then
            cb.Text:SetText(label)
            cb.Text:SetFontObject(GameFontHighlightSmall)
        else
            _G[cb:GetName() .. "Text"] = nil
            local fs = cb:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
            fs:SetPoint("LEFT", cb, "RIGHT", 2, 0)
            fs:SetText(label)
        end
        local nameKey = strlower(entry.name)
        cb:SetChecked(store.inputChannels[nameKey] and true or false)
        cb:SetScript("OnClick", function(self)
            store.inputChannels[nameKey] = self:GetChecked() and true or nil
        end)
        channelListChildren[#channelListChildren + 1] = cb
        channelCheckboxes[nameKey] = cb
        lastFrame = cb
        yOffset = -2
        totalHeight = totalHeight + 22
    end
    return lastFrame, totalHeight
end

local function buildOutputList(parent, anchorTop, store)
    clearChildren(outputListChildren)
    wipe(outputCheckboxes)

    local defs = {
        { key = "self",       label = "Self (default chat frame)" },
        { key = "scanWindow", label = "ChatScan window (separate tab)" },
    }

    local lastFrame = anchorTop
    local yOffset = -4
    local totalHeight = 0
    for _, def in ipairs(defs) do
        local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
        cb:SetSize(20, 20)
        cb:SetPoint("TOPLEFT", lastFrame, "BOTTOMLEFT", 0, yOffset)
        if cb.Text then
            cb.Text:SetText(def.label)
            cb.Text:SetFontObject(GameFontHighlightSmall)
        else
            local fs = cb:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
            fs:SetPoint("LEFT", cb, "RIGHT", 2, 0)
            fs:SetText(def.label)
        end
        cb:SetChecked(store.outputs[def.key] and true or false)
        cb:SetScript("OnClick", function(self)
            store.outputs[def.key] = self:GetChecked() and true or false
        end)
        outputListChildren[#outputListChildren + 1] = cb
        outputCheckboxes[def.key] = cb
        lastFrame = cb
        yOffset = -2
        totalHeight = totalHeight + 22
    end
    return lastFrame, totalHeight
end

local function buildPanel()
    local f = CreateFrame("Frame", "GetInTouchChatScanPanel", UIParent, "BackdropTemplate")
    f:SetSize(360, 460)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    if f.SetBackdrop then
        f:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        f:SetBackdropColor(0, 0, 0, 0.9)
    end

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)

    local title = f:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -10)
    title:SetText("Chat Scan")

    local channelsLabel = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    channelsLabel:SetPoint("TOPLEFT", 14, -36)
    channelsLabel:SetText("Channels")
    f.channelsLabel = channelsLabel

    local channelContainer = CreateFrame("Frame", nil, f)
    channelContainer:SetPoint("TOPLEFT", channelsLabel, "BOTTOMLEFT", 0, -4)
    channelContainer:SetPoint("RIGHT", f, "RIGHT", -14, 0)
    channelContainer:SetHeight(20)
    f.channelContainer = channelContainer

    local keywordsLabel = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    keywordsLabel:SetPoint("TOPLEFT", channelContainer, "BOTTOMLEFT", 0, -10)
    keywordsLabel:SetText("Keywords")
    f.keywordsLabel = keywordsLabel

    local helper = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    helper:SetPoint("TOPLEFT", keywordsLabel, "BOTTOMLEFT", 0, -4)
    helper:SetPoint("RIGHT", f, "RIGHT", -14, 0)
    helper:SetJustifyH("LEFT")
    helper:SetWordWrap(true)
    helper:SetText("Separate keywords with commas. Use + to require multiple keywords in the same message. Example: wts thunderfury, lf+tank, lf+heal matches any message containing 'wts thunderfury', or both 'lf' AND 'tank', or both 'lf' AND 'heal'.")
    f.helper = helper

    local editHost = CreateFrame("ScrollFrame", "GetInTouchChatScanEditScroll", f, "InputScrollFrameTemplate")
    editHost:SetPoint("TOPLEFT", helper, "BOTTOMLEFT", 0, -6)
    editHost:SetPoint("RIGHT", f, "RIGHT", -22, 0)
    editHost:SetHeight(90)
    editHost.CharCount:Hide()
    local eb = editHost.EditBox
    eb:SetFontObject(ChatFontNormal)
    eb:SetMaxLetters(1024)
    eb:SetAutoFocus(false)
    eb:SetWidth(editHost:GetWidth() - 18)
    keywordEditBox = eb
    f.editHost = editHost

    local outputsLabel = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    outputsLabel:SetPoint("TOPLEFT", editHost, "BOTTOMLEFT", -4, -10)
    outputsLabel:SetText("Output destinations")
    f.outputsLabel = outputsLabel

    local outputContainer = CreateFrame("Frame", nil, f)
    outputContainer:SetPoint("TOPLEFT", outputsLabel, "BOTTOMLEFT", 0, -4)
    outputContainer:SetPoint("RIGHT", f, "RIGHT", -14, 0)
    outputContainer:SetHeight(20)
    f.outputContainer = outputContainer

    local closeBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    closeBtn:SetSize(80, 22)
    closeBtn:SetPoint("BOTTOMLEFT", 12, 12)
    closeBtn:SetText("Close")
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    local startBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    startBtn:SetSize(100, 22)
    startBtn:SetPoint("BOTTOMRIGHT", -12, 12)
    startBtn:SetText("Start Scan")
    local startTex = startBtn:GetNormalTexture()
    if startTex then startTex:SetVertexColor(1, 0.35, 0.35) end
    local startHi = startBtn:GetHighlightTexture()
    if startHi then startHi:SetVertexColor(1, 0.5, 0.5) end
    startBtn:SetScript("OnClick", function()
        local store = ensureDB()
        store.keywordText = keywordEditBox:GetText() or ""
        status("Settings saved.")
        if startScan() then
            f:Hide()
        end
    end)

    local saveBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    saveBtn:SetSize(80, 22)
    saveBtn:SetPoint("RIGHT", startBtn, "LEFT", -6, 0)
    saveBtn:SetText("Save")
    saveBtn:SetScript("OnClick", function()
        local store = ensureDB()
        store.keywordText = keywordEditBox:GetText() or ""
        status("Settings saved.")
    end)

    f:SetScript("OnShow", function()
        local store = ensureDB()
        local last, height = rebuildChannelList(channelContainer, channelsLabel, store)
        channelContainer:SetHeight(math.max(height, 16))
        keywordsLabel:ClearAllPoints()
        keywordsLabel:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, -10)

        keywordEditBox:SetText(store.keywordText or "")
        keywordEditBox:SetCursorPosition(0)
        C_Timer.After(0, function()
            if f:IsShown() and keywordEditBox then keywordEditBox:SetFocus() end
        end)

        local _, outHeight = buildOutputList(outputContainer, outputsLabel, store)
        outputContainer:SetHeight(math.max(outHeight, 16))

        local extraChannels = math.max(0, height - 20)
        local extraOutputs = math.max(0, outHeight - 44)
        f:SetHeight(360 + extraChannels + extraOutputs)
    end)

    tinsert(UISpecialFrames, "GetInTouchChatScanPanel")

    f:Hide()
    return f
end

local function togglePanel()
    if not panel then panel = buildPanel() end
    if panel:IsShown() then panel:Hide() else panel:Show() end
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        ensureDB()
    elseif event == "PLAYER_LOGIN" then
        local store = ensureDB()
        if store.scanEnabled then
            applySettingsToRuntime(store)
            if #parsedGroups > 0
               and countTable(selectedChannelNames) > 0
               and countTable(selectedOutputs) > 0 then
                if not scanFrame:IsEventRegistered("CHAT_MSG_CHANNEL") then
                    scanFrame:RegisterEvent("CHAT_MSG_CHANNEL")
                end
                scanning = true
                status(string.format("Scanning %d channel(s) for %d keyword group(s).",
                    countTable(selectedChannelNames), #parsedGroups))
            else
                store.scanEnabled = false
            end
        end
    end
end)

SLASH_CHATSCAN1 = "/chatscan"
SLASH_CHATSCAN2 = "/cs"
SlashCmdList["CHATSCAN"] = function(input)
    input = (input or ""):match("^%s*(.-)%s*$"):lower()
    if input == "start" then
        startScan()
    elseif input == "stop" then
        stopScan()
    else
        togglePanel()
    end
end
