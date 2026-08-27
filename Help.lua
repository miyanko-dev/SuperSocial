local _, ns = ...

-- A scrollable reference panel for every command and option, opened with "/ss". Styled after the Target Finder panel so the two addons read as one family: dialog-box backdrop, header banner, and bordered section containers.

local PANEL_WIDTH = 480
local PANEL_HEIGHT = 580
local PANEL_PAD = 14
local PANEL_PAD_TOP = 52       -- clears the dialog-box-header banner
local PANEL_PAD_BOTTOM = 14
local SCROLLBAR_GUTTER = 22    -- room for the scroll bar the template hangs outside its right edge
local SECTION_GAP = 26         -- also clears the section label riding above each box
local SECTION_INNER_PAD = 12
local SECTION_LABEL_LIFT = 7
local LABEL_WIDTH = 116
local COLUMN_GAP = 12
local ROW_GAP = 10

local YELLOW = "|cffffd200"

-- The panel is four sections: the slash commands, the click shortcuts, the /ss management subcommands, then the flags that refine /ww. "cmd" is the yellow left-column label; "eg" carries the full worked example so the column stays scannable.
local INTRO =
    "Run /who, then /ww whispers everyone in the results — that's the core idea. "
    .. "The flags below refine who hears it, and they stack in any order before the message. "

local COMMANDS = {
    {
        cmd = "/ww",
        desc = "Whisper everyone in your current /who results.",
        eg = "/ww LFM SM live, need a tank",
    },
    {
        cmd = "/wt",
        desc = "Whisper your current target (a player you have selected).",
        eg = "/wt got room for one more?",
    },
    {
        cmd = "/ws",
        desc = "Whisper every seller in the auction house Browse tab.",
        eg = "/ws still selling your Black Lotus?",
    },
    {
        cmd = "/rr",
        desc = "Reply to everyone whispered via /ww who whispered back and hasn't been answered yet. On its own it reports how many are waiting.",
        eg = "/rr invite incoming, whisper me",
    },
    {
        cmd = "/ss",
        desc = "Open this reference panel.",
        eg = "/ss",
    },
}

local MANAGE = {
    {
        cmd = "/ss stop",
        desc = "Cancel any whispers still queued to send.",
        eg = "/ss stop",
    },
    {
        cmd = "/ss quiet",
        desc = "Replace your own outgoing lines during a run with one Y/Z counter that ticks in place, so the replies they draw aren't buried. The run still names the message it sends, and closes with its verdict on a fresh line at the bottom. Covers /ww, /ws and /rr; /wt always prints. On by default. /ss quiet on and /ss quiet off set it outright.",
        eg = "/ss quiet",
    },
    {
        cmd = "/ss rate",
        desc = "Show the learned send rate in whispers per second.",
        eg = "/ss rate",
    },
    {
        cmd = "/ss rate reset",
        desc = "Restore the default send rate; the server re-teaches it from there.",
        eg = "/ss rate reset",
    },
    {
        cmd = "/ss -ignore",
        desc = "Show how many names are on the ignore list and how old the oldest one is.",
        eg = "/ss -ignore",
    },
    {
        cmd = "/ss -ignore NAME",
        desc = "Add a player to the ignore list by hand — the same list -ignore sends build.",
        eg = "/ss -ignore Thrall",
    },
    {
        cmd = "/ss -ignore clear",
        desc = "Empty the ignore list.",
        eg = "/ss -ignore clear",
    },
    {
        cmd = "/ss -cd clear",
        desc = "Empty the cooldown history.",
        eg = "/ss -cd clear",
    },
    {
        cmd = "/ss -block NAME",
        desc = "Block a player for good: no command ever whispers them. Account-wide; /ss -ignore clear leaves it alone.",
        eg = "/ss -block Thrall",
    },
    {
        cmd = "/ss -block list",
        desc = "Show everyone on the block list.",
        eg = "/ss -block list",
    },
    {
        cmd = "/ss -unblock NAME",
        desc = "Remove a player from the block list.",
        eg = "/ss -unblock Thrall",
    },
}

local SHORTCUTS = {
    {
        cmd = "Shift-click",
        desc = "With the macro window open and no chat box waiting, paste a Questie tracker quest into the macro body instead of untracking it.",
        eg = "Shift-click a tracked quest while editing a macro",
    },
}

local SHORTCUT_TARGETS =
    "The Questie paste needs the macro window open with a macro selected; an open chat box always gets the link first."

local FLAGS = {
    {
        cmd = "-limit N",
        on = "/ww, /rr, /ws",
        desc = "Whisper only the first N recipients.",
        eg = "/ww -limit 10 LFM SM live",
    },
    {
        cmd = "-skip",
        on = "/ww",
        desc = "Skip anyone whose class, zone or name contains the word (Warrior, Maraudon, Xander, …). Separate several with commas.",
        eg = "/ww -skip Warlock, Maraudon LFM healer",
    },
    {
        cmd = "-only",
        on = "/ww",
        desc = "The inverse of -skip: whisper only players matching a class, zone or name. Separate several with commas.",
        eg = "/ww -only Priest, Paladin LFM healer",
    },
    {
        cmd = "-ignore",
        on = "/ww, /wt, /ws",
        desc = "Skip anyone on the ignore list, then add the people you whisper to it. Survives reloads, entries age out after 30 days; clear with /ss -ignore clear.",
        eg = "/ww -ignore WTS enchant mats, whisper me",
    },
    {
        cmd = "-cd M",
        on = "/ww, /ws",
        desc = "Skip anyone whispered in the last M minutes, then put new recipients on an M-minute cooldown.",
        eg = "/ww -cd 30 WTB Black Lotus, paying 80g",
    },
    {
        cmd = "-cd",
        on = "/ww, /ws",
        desc = "With no number, skip anyone already cooling down without recording the people you whisper.",
        eg = "/ww -cd LFM SM live, need 1 tank",
    },
    {
        cmd = "-who",
        on = "/ww",
        desc = "Run the /who search yourself: results skip chat and the panel stays closed. The filter is level ranges and keyed terms (c- z- r- n- g-); the first word shaped like neither starts the message.",
        eg = "/ww -who 57-59 c-warrior -cd 60 LFM tank for BRD",
    },
    {
        cmd = "-wait",
        on = "/ww",
        desc = "Hold the whisper until fresh /who results arrive, for a two-line macro with its own /who. -who replaces this in one line.",
        eg = "/ww -wait -limit 20 WTB Black Lotus",
    },
    {
        cmd = ";",
        on = "/ww, /wt, /ws, /rr",
        desc = "Split the message: each recipient gets every part as its own whisper, back to back.",
        eg = "/ww Hey, how are you? ; up for tanking Scholo?",
    },
}

local FOOTER =
    "Stack flags freely: /ww -limit 20 -skip Maraudon -cd 30 LFM tank for SM "
    .. "whispers up to 20 people, skips anyone in Maraudon, and won't repeat within 30 minutes. "
    .. "Flags go before the message."

-- Dialog-box header banner reconstructed from three texture pieces (left cap, repeating middle, right cap), matching the Target Finder title.
local function buildTitleHeader(parent, text)
    local HEADER_TEXTURE = "Interface\\DialogFrame\\UI-DialogBox-Header"

    local mid = parent:CreateTexture(nil, "OVERLAY")
    mid:SetTexture(HEADER_TEXTURE)
    mid:SetTexCoord(0.31, 0.67, 0, 0.63)
    mid:SetPoint("TOP", parent, "TOP", 0, 12)
    mid:SetHeight(40)

    local left = parent:CreateTexture(nil, "OVERLAY")
    left:SetTexture(HEADER_TEXTURE)
    left:SetTexCoord(0.21, 0.31, 0, 0.63)
    left:SetPoint("RIGHT", mid, "LEFT")
    left:SetWidth(30)
    left:SetHeight(40)

    local right = parent:CreateTexture(nil, "OVERLAY")
    right:SetTexture(HEADER_TEXTURE)
    right:SetTexCoord(0.67, 0.77, 0, 0.63)
    right:SetPoint("LEFT", mid, "RIGHT")
    right:SetWidth(30)
    right:SetHeight(40)

    local title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", mid, "TOP", 0, -14)
    title:SetText(text)

    mid:SetWidth((title:GetStringWidth() or 0) + 10)
end

-- Bordered section container with its yellow label riding on the top edge, matching the Target Finder sections.
local function buildSection(parent, labelText)
    local section = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    section:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = { left = 3, right = 3, top = 5, bottom = 3 },
    })
    section:SetBackdropColor(0.1, 0.1, 0.1, 0.5)
    section:SetBackdropBorderColor(0.4, 0.4, 0.4)

    local label = section:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("BOTTOMLEFT", section, "TOPLEFT", 12, SECTION_LABEL_LIFT)
    label:SetText(labelText)

    return section
end

-- One two-column row: yellow command label left, white description with a yellow example beneath on the right. Returns the row height.
local function buildRow(section, y, width, label, body)
    local bodyLeft = SECTION_INNER_PAD + LABEL_WIDTH + COLUMN_GAP

    local left = section:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    left:SetPoint("TOPLEFT", SECTION_INNER_PAD, -y)
    left:SetWidth(LABEL_WIDTH)
    left:SetJustifyH("LEFT")
    left:SetText(label)

    local right = section:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    right:SetPoint("TOPLEFT", bodyLeft, -y - 1)
    right:SetWidth(width - bodyLeft - SECTION_INNER_PAD)
    right:SetJustifyH("LEFT")
    right:SetSpacing(2)
    right:SetText(body)

    return math.max(left:GetStringHeight(), right:GetStringHeight())
end

local function exampleLine(text)
    return "e.g.  " .. YELLOW .. text .. "|r"
end

-- Lay one section's entries and return the section frame with its height set.
local function layoutSection(content, width, labelText, entries, describe)
    local section = buildSection(content, labelText)
    local y = SECTION_INNER_PAD
    for _, entry in ipairs(entries) do
        y = y + buildRow(section, y, width, entry.cmd, describe(entry)) + ROW_GAP
    end
    section:SetHeight(y - ROW_GAP + SECTION_INNER_PAD)
    return section
end

-- Full-width white note, used for the intro and the closing combination example.
local function buildNote(content, y, width, text)
    local note = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    note:SetPoint("TOPLEFT", PANEL_PAD, -y)
    note:SetWidth(width - PANEL_PAD * 2)
    note:SetJustifyH("LEFT")
    note:SetSpacing(2)
    note:SetText(text)
    return note:GetStringHeight()
end

local helpFrame

local function buildFrame()
    local panel = CreateFrame("Frame", "SuperSocialHelpFrame", UIParent, "BackdropTemplate")
    panel:SetSize(PANEL_WIDTH, PANEL_HEIGHT)
    panel:SetPoint("CENTER")
    panel:SetFrameStrata("DIALOG")
    panel:SetClampedToScreen(true)
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
    panel:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 },
    })
    tinsert(UISpecialFrames, "SuperSocialHelpFrame")

    buildTitleHeader(panel, "Super Social")

    local cornerClose = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    cornerClose:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -6, -6)

    local scroll = CreateFrame("ScrollFrame", "SuperSocialHelpScroll", panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", PANEL_PAD, -PANEL_PAD_TOP)
    scroll:SetPoint("BOTTOMRIGHT", -PANEL_PAD - SCROLLBAR_GUTTER, PANEL_PAD_BOTTOM)

    local content = CreateFrame("Frame", nil, scroll)
    scroll:SetScrollChild(content)
    local width = scroll:GetWidth()
    content:SetWidth(width)

    local y = 4
    y = y + buildNote(content, y, width, INTRO) + SECTION_GAP

    local function withExample(e) return e.desc .. "\n" .. exampleLine(e.eg) end

    local sections = {
        { label = "Commands", entries = COMMANDS, describe = withExample },
        { label = "Shortcuts", entries = SHORTCUTS, describe = withExample, note = SHORTCUT_TARGETS },
        { label = "Manage", entries = MANAGE, describe = withExample },
        { label = "Flags", entries = FLAGS, describe = function(e) return e.desc .. "  (" .. e.on .. ")\n" .. exampleLine(e.eg) end },
    }
    for _, spec in ipairs(sections) do
        local section = layoutSection(content, width, spec.label, spec.entries, spec.describe)
        section:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
        section:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -y)
        y = y + section:GetHeight()
        -- A section note sits tight under its box, not a full section gap away.
        if spec.note then
            y = y + ROW_GAP + buildNote(content, y + ROW_GAP, width, spec.note)
        end
        y = y + SECTION_GAP
    end

    y = y + buildNote(content, y, width, FOOTER)
    content:SetHeight(y + PANEL_PAD_BOTTOM)

    panel:Hide()
    helpFrame = panel
end

-- Built lazily on first open so we never create frames during file load.
function ns.ToggleHelp()
    if not helpFrame then buildFrame() end
    if helpFrame:IsShown() then
        helpFrame:Hide()
    else
        helpFrame:Show()
    end
end
