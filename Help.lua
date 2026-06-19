local _, ns = ...

-- A scrollable reference window for every command and option, opened with
-- "/wta". Replaces the old chat dump, which scrolled away and was hard to read.

local tint = ns.tint

-- Each entry is a command or option with what it does and a worked example.
-- "cmd" is the short label shown in the left column; the example carries the
-- full usage so the column stays narrow and scannable.
local COMMANDS = {
    {
        cmd = "/ww",
        desc = "Whisper everyone in your current /who results.",
        eg = "/ww LFM SM live, need a tank",
    },
    {
        cmd = "/wt",
        desc = "Whisper your current target.",
        eg = "/wt got room for one more?",
    },
    {
        cmd = "/ws",
        desc = "Whisper every seller in the auction house Browse tab.",
        eg = "/ws still selling your Black Lotus?",
    },
    {
        cmd = "/rr",
        desc = "Reply to everyone from your last /ww who whispered you back. Each /ww starts a fresh batch.",
        eg = "/rr invite incoming, whisper me",
    },
    {
        cmd = "/wta",
        desc = "Open this window. Add stop, reset, clear cd, or clear all to manage queued whispers and saved lists.",
        eg = "/wta stop",
    },
}

local OPTIONS = {
    {
        cmd = "-N",
        on = "/ww, /rr",
        desc = "Whisper only the first N recipients.",
        eg = "/ww -10 LFM SM live",
    },
    {
        cmd = "-not",
        on = "/ww",
        desc = "Skip anyone whose class or zone contains the word (Warrior, Maraudon, …). Separate several with commas.",
        eg = "/ww -not Warlock, Maraudon LFM healer",
    },
    {
        cmd = "-only",
        on = "/ww",
        desc = "The inverse of -not: whisper only players matching a class or zone. Separate several with commas.",
        eg = "/ww -only Priest, Paladin LFM healer",
    },
    {
        cmd = "-skip",
        on = "/ww, /wt",
        desc = "Skip anyone on the skip list, then add the people you whisper to it. Survives reloads.",
        eg = "/ww -skip WTS enchant mats, whisper me",
    },
    {
        cmd = "-cd M",
        on = "/ww",
        desc = "Skip anyone whispered in the last M minutes, then put new recipients on an M-minute cooldown.",
        eg = "/ww -cd 30 WTB Black Lotus, paying 80g",
    },
    {
        cmd = "-cd",
        on = "/ww",
        desc = "With no number, skip anyone already cooling down without recording the people you whisper.",
        eg = "/ww -cd LFM SM live, need 1 tank",
    },
}

-- Lay the entries out as a two-column table: gold label on the left, white
-- description with an amber example beneath on the right. Each section gets a
-- larger heading. Returns the total content height.
local function layoutContent(content, width)
    local LEFT, RIGHT = 16, 10
    local LABEL_WIDTH, COLUMN_GAP = 92, 14
    local bodyLeft = LEFT + LABEL_WIDTH + COLUMN_GAP
    local bodyWidth = width - bodyLeft - RIGHT
    local y = 12

    local function addHeader(text)
        y = y + 8
        local header = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        header:SetPoint("TOPLEFT", LEFT, -y)
        header:SetText(text)
        y = y + header:GetStringHeight() + 10
    end

    local function addRow(label, body)
        local left = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        left:SetPoint("TOPLEFT", LEFT, -y)
        left:SetWidth(LABEL_WIDTH)
        left:SetJustifyH("LEFT")
        left:SetText(label)

        local right = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        right:SetPoint("TOPLEFT", bodyLeft, -y - 1)
        right:SetWidth(bodyWidth)
        right:SetJustifyH("LEFT")
        right:SetSpacing(2)
        right:SetText(body)

        y = y + math.max(left:GetStringHeight(), right:GetStringHeight()) + 12
    end

    local function exampleLine(text)
        return tint("muted", "e.g.  ") .. tint("cool", text)
    end

    addHeader("Commands")
    for _, entry in ipairs(COMMANDS) do
        addRow(entry.cmd, entry.desc .. "\n" .. exampleLine(entry.eg))
    end

    addHeader("Options")
    for _, entry in ipairs(OPTIONS) do
        local desc = entry.desc .. "  " .. tint("muted", "(" .. entry.on .. ")")
        addRow(entry.cmd, desc .. "\n" .. exampleLine(entry.eg))
    end

    return y + 8
end

local helpFrame

local function buildFrame()
    local frame = CreateFrame("Frame", "WhisperThemAllHelpFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(500, 560)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("HIGH")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame.TitleText:SetText("Whisper Them All")

    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

    -- Let Escape close it like other panels.
    tinsert(UISpecialFrames, "WhisperThemAllHelpFrame")

    local scroll = CreateFrame("ScrollFrame", "WhisperThemAllHelpScroll", frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 10, -30)
    scroll:SetPoint("BOTTOMRIGHT", -30, 8)

    local content = CreateFrame("Frame", nil, scroll)
    scroll:SetScrollChild(content)

    local width = scroll:GetWidth()
    content:SetSize(width, layoutContent(content, width))

    frame:Hide()
    helpFrame = frame
end

-- Built lazily on first open so we never create frames during file load.
function ns.toggleHelp()
    if not helpFrame then buildFrame() end
    if helpFrame:IsShown() then
        helpFrame:Hide()
    else
        helpFrame:Show()
    end
end
