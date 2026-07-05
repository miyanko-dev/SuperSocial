local _, ns = ...

-- A scrollable reference window for every command and option, opened with
-- "/wta". Replaces the old chat dump, which scrolled away and was hard to read.

local tint = ns.tint

-- The window is three sections: the slash commands, the /wta management
-- subcommands, then the flags that refine /ww. "cmd" is the short left-column
-- label; "eg" carries the full worked example so the column stays scannable.
local INTRO =
    "Run /who, then /ww whispers everyone in the results — that's the core idea. "
    .. "The flags below refine who hears it, and they stack in any order."

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
        desc = "Reply to everyone from your last /ww who whispered you back. Each /ww starts a fresh batch.",
        eg = "/rr invite incoming, whisper me",
    },
    {
        cmd = "/wta",
        desc = "Open this reference window.",
        eg = "/wta",
    },
}

-- Management subcommands: the label is the whole command, so these rows carry
-- no separate example.
local MANAGE = {
    {
        cmd = "/wta stop",
        desc = "Cancel any whispers still queued to send.",
    },
    {
        cmd = "/wta clear",
        desc = "Empty the ignore list (/wta reset does the same).",
    },
    {
        cmd = "/wta clear cd",
        desc = "Empty the cooldown history.",
    },
    {
        cmd = "/wta clear all",
        desc = "Empty both the ignore list and the cooldown history.",
    },
}

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
        desc = "Skip anyone whose class or zone contains the word (Warrior, Maraudon, …). Separate several with commas.",
        eg = "/ww -skip Warlock, Maraudon LFM healer",
    },
    {
        cmd = "-only",
        on = "/ww",
        desc = "The inverse of -skip: whisper only players matching a class or zone. Separate several with commas.",
        eg = "/ww -only Priest, Paladin LFM healer",
    },
    {
        cmd = "instance",
        on = "-skip, -only",
        desc = "A keyword that expands to every dungeon and raid name, so -skip instance skips anyone already inside one.",
        eg = "/ww -skip instance LFM tank for SM",
    },
    {
        cmd = "-ignore",
        on = "/ww, /wt, /ws",
        desc = "Skip anyone on the ignore list, then add the people you whisper to it. Survives reloads; clear with /wta clear.",
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
}

local FOOTER =
    "Stack flags freely: /ww -limit 20 -skip instance -cd 30 LFM tank for SM "
    .. "whispers up to 20 people, skips anyone already in an instance, and won't repeat within 30 minutes."

-- Lay the entries out as a two-column table: gold label on the left, white
-- description with an amber example beneath on the right. Full-width notes lead
-- and close the page, and each section gets a larger heading. Returns the total
-- content height.
local function layoutContent(content, width)
    local LEFT, RIGHT = 16, 10
    local LABEL_WIDTH, COLUMN_GAP = 104, 14
    local bodyLeft = LEFT + LABEL_WIDTH + COLUMN_GAP
    local bodyWidth = width - bodyLeft - RIGHT
    local y = 12

    local function addNote(text)
        local note = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        note:SetPoint("TOPLEFT", LEFT, -y)
        note:SetWidth(width - LEFT - RIGHT)
        note:SetJustifyH("LEFT")
        note:SetSpacing(2)
        note:SetText(text)
        y = y + note:GetStringHeight() + 12
    end

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

    addNote(INTRO)

    addHeader("Commands")
    for _, entry in ipairs(COMMANDS) do
        addRow(entry.cmd, entry.desc .. "\n" .. exampleLine(entry.eg))
    end

    addHeader("Manage")
    for _, entry in ipairs(MANAGE) do
        addRow(entry.cmd, entry.desc)
    end

    addHeader("Flags")
    for _, entry in ipairs(FLAGS) do
        local desc = entry.desc .. "  " .. tint("muted", "(" .. entry.on .. ")")
        addRow(entry.cmd, desc .. "\n" .. exampleLine(entry.eg))
    end

    addHeader("Combine them")
    addNote(FOOTER)

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
