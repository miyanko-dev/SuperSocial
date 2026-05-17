local helpPanel

local COMMAND_SECTIONS = {
    {
        title = "Whisper target",
        rows = {
            { "/wt MESSAGE", "whisper your current target" },
            { "/wt+ MESSAGE", "whisper target and remember" },
            { "/wta list", "open the remembered-name list" },
        },
    },
    {
        title = "Whisper /who results",
        rows = {
            { "/ww MESSAGE", "whisper everyone in /who results" },
            { "/ww -N MESSAGE", "whisper first N players in /who results" },
            { "/ww -N -FILTER... MSG", "exclude players by class, name, or zone" },
            { "/ww+ ... MESSAGE", "whisper /who results and remember" },
            { "/wta clear", "clear the remembered whisper list" },
        },
    },
    {
        title = "Whisper auction sellers",
        rows = {
            { "/ws MESSAGE", "whisper all sellers in the AH Browse tab" },
        },
    },
    {
        title = "Reply",
        rows = {
            { "/rr MESSAGE", "reply to all recent whisperers" },
            { "/rr N MESSAGE", "reply to the last N whisperers" },
            { "/rr reset", "clear the session reply list" },
        },
    },
    {
        title = "Port",
        rows = {
            { "/port", "find mages in your current zone" },
            { "/port ZONE", "find warlocks in the specified zone" },
        },
    },
}

local function buildHelpPanel()
    local f = CreateFrame("Frame", "WhisperThemAllHelpPanel", UIParent, "BackdropTemplate")
    f:SetSize(440, 480)
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
    title:SetPoint("TOP", 0, -12)
    title:SetText("WhisperThemAll -- Commands")

    local intro = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    intro:SetPoint("TOPLEFT", 12, -38)
    intro:SetPoint("TOPRIGHT", -12, -38)
    intro:SetJustifyH("LEFT")
    intro:SetWordWrap(true)
    intro:SetText("Bulk-whisper, reply, and find ports without rebinding the chat box.")

    local scroll = CreateFrame("ScrollFrame", "$parentScroll", f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 12, -72)
    scroll:SetPoint("BOTTOMRIGHT", -28, 44)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(380, 1)
    scroll:SetScrollChild(content)

    local yOffset = 0
    for _, section in ipairs(COMMAND_SECTIONS) do
        local label = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        label:SetPoint("TOPLEFT", 0, -yOffset)
        label:SetText(section.title)
        yOffset = yOffset + 20
        for _, row in ipairs(section.rows) do
            local cmd = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
            cmd:SetPoint("TOPLEFT", 8, -yOffset)
            cmd:SetWidth(170)
            cmd:SetJustifyH("LEFT")
            cmd:SetText("|cffffff00" .. row[1] .. "|r")
            local desc = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
            desc:SetPoint("TOPLEFT", cmd, "TOPRIGHT", 8, 0)
            desc:SetPoint("RIGHT", content, "RIGHT", -4, 0)
            desc:SetJustifyH("LEFT")
            desc:SetWordWrap(true)
            desc:SetText(row[2])
            yOffset = yOffset + 18
        end
        yOffset = yOffset + 8
    end
    content:SetHeight(math.max(yOffset, 1))

    local closeBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    closeBtn:SetSize(80, 22)
    closeBtn:SetPoint("BOTTOMRIGHT", -12, 12)
    closeBtn:SetText("Close")
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    tinsert(UISpecialFrames, "WhisperThemAllHelpPanel")
    f:Hide()
    return f
end

local function showHelp()
    if not helpPanel then helpPanel = buildHelpPanel() end
    if not helpPanel:IsShown() then helpPanel:Show() end
end

local function handleSlash(input)
    input = (input or ""):match("^%s*(.-)%s*$"):lower()
    if input == "clear" then
        if WhisperThemAll and WhisperThemAll.ClearIgnore then
            WhisperThemAll.ClearIgnore()
        end
        return
    end
    if input == "list" then
        if WhisperThemAll and WhisperThemAll.ToggleIgnorePanel then
            WhisperThemAll.ToggleIgnorePanel()
        end
        return
    end
    showHelp()
end

SLASH_WHISPERTHEMALL1 = "/wta"
SlashCmdList["WHISPERTHEMALL"] = handleSlash

local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", function(self)
    print("|cffffff00[WhisperThemAll]:|r Loaded. Type /wta for available commands.")
    self:UnregisterEvent("PLAYER_LOGIN")
end)