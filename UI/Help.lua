local _, ns = ...

-- A scrollable reference panel for every command and option, opened with "/ss". Built from Blizzard's own ButtonFrameTemplate window, inset boxes, scroll frame and font objects, so it wears the client's own chrome.

local PANEL_NAME = "SuperSocialFrame"
local PANEL_ICON = 134149      -- the toc IconTexture
local PANEL_WIDTH = 480
local PANEL_HEIGHT = 580
local ATTIC_PAD = 6            -- the intro's gap below the title bar
local INSET_PAD = 8            -- content sits this far inside the inset
local SECTION_GAP = 26         -- also clears the section label riding above each box
local SECTION_INNER_PAD = 12
local SECTION_LABEL_LIFT = 7
local LABEL_WIDTH = 116
local COLUMN_GAP = 12
local ROW_GAP = 10

-- The attic holds the one-line idea and a hint; the inset below holds three sections: the slash commands, the /ss management subcommands, then the flags that refine /ww. "cmd" is the gold left-column label; "eg" carries the full worked example so the column stays scannable.
local INTRO = "Run /who, then /ww MESSAGE whispers every result."
local INTRO_HINT = "Flags refine who hears it and stack in any order before the message."

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
        desc = "Whisper every seller in the item listings open in the auction house. The Browse list names no sellers, so open an item first. Your own auctions are skipped.",
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
        desc = "Cancel any whispers still queued to send. Anyone you were mid-reply to goes back on the /rr list.",
        eg = "/ss stop",
    },
    {
        cmd = "/ss quiet",
        desc = "Replace your own outgoing lines during a run with one Y/Z counter that ticks in place, so the replies they draw aren't buried. The run still names the message it sends, and closes with its verdict on a fresh line at the bottom. Covers every bulk command; /wt always prints. On by default. /ss quiet on and /ss quiet off set it outright.",
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
        cmd = "/ss -cd",
        desc = "Show how many names are on cooldown and how long the longest one still runs.",
        eg = "/ss -cd",
    },
    {
        cmd = "/ss -cd NAME",
        desc = "Put a player on cooldown by hand — the same list -cd sends build. 30 days unless you add a duration.",
        eg = "/ss -cd Thrall 2h",
    },
    {
        cmd = "/ss -cd clear",
        desc = "Empty the cooldown list.",
        eg = "/ss -cd clear",
    },
    {
        cmd = "/ss -block NAME",
        desc = "Block a player for good: no command ever whispers them. Account-wide; /ss -cd clear leaves it alone.",
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

local FLAGS = {
    {
        cmd = "-limit N",
        on = { "/ww", "/rr", "/ws" },
        desc = "Whisper only the first N recipients.",
        eg = "/ww -limit 10 LFM SM live",
    },
    {
        cmd = "-skip (…)",
        on = { "/ww" },
        desc = "Skip anyone whose class, zone or name contains a word in the brackets. Lead a word with c- z- n- to match only that field; quote phrases with spaces.",
        eg = "/ww -skip (warlock z-maraudon) LFM healer",
    },
    {
        cmd = "-only (…)",
        on = { "/ww" },
        desc = "The inverse of -skip: whisper only players matching a word in the brackets. Same c- z- n- keys. When a player matches both, -skip wins.",
        eg = "/ww -only (priest c-paladin) LFM healer",
    },
    {
        cmd = "-cd D",
        on = { "/ww", "/wt", "/ws" },
        desc = "Skip anyone still on cooldown, then put new recipients on cooldown for D: minutes by default, or 30m, 2h, 30d. Account-wide, survives reloads; 30d is the long memory for a pitch nobody should hear twice.",
        eg = "/ww -cd 30d WTS enchant mats, whisper me",
    },
    {
        cmd = "-cd",
        on = { "/ww", "/ws" },
        desc = "With no duration, skip anyone already cooling down without recording the people you whisper.",
        eg = "/ww -cd LFM SM live, need 1 tank",
    },
    {
        cmd = "-who (…)",
        on = { "/ww" },
        desc = "Run the /who search yourself: results skip chat and the panel stays closed. The brackets take anything /who accepts (class, zone, name, level range, c- z- n- g- r- terms).",
        eg = "/ww -who (warrior 57-59) -cd 60 LFM tank for BRD",
    },
    {
        cmd = ";",
        on = { "/ww", "/wt", "/ws", "/rr" },
        desc = "Split the message: each recipient gets every part as its own whisper, back to back.",
        eg = "/ww Hey, how are you? ; up for tanking Scholo?",
    },
}

local FOOTER =
    "Stack flags freely: /ww -who (55-60) -limit 20 -skip (z-maraudon) -cd 30 LFM tank for SM "
    .. "searches levels 55 to 60, whispers up to 20 of them, skips anyone in Maraudon, and won't repeat within 30 minutes. "
    .. "Flags go before the message; anything with more than one word goes in brackets."

-- Bordered section container, the game's own inset box, with its gold label riding on the top edge.
local function buildSection(parent, labelText)
    local section = CreateFrame("Frame", nil, parent, "InsetFrameTemplate")

    local label = section:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("BOTTOMLEFT", section, "TOPLEFT", 4, SECTION_LABEL_LIFT)
    label:SetText(labelText)

    return section
end

-- One two-column row: gold command label left, white description with a gold example beneath on the right. Returns the row height.
local function buildRow(section, y, width, label, body)
    local bodyLeft = SECTION_INNER_PAD + LABEL_WIDTH + COLUMN_GAP

    local left = section:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    left:SetPoint("TOPLEFT", SECTION_INNER_PAD, -y)
    left:SetWidth(LABEL_WIDTH)
    left:SetJustifyH("LEFT")
    left:SetText(label)

    local right = section:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    right:SetPoint("TOPLEFT", bodyLeft, -y)
    right:SetWidth(width - bodyLeft - SECTION_INNER_PAD)
    right:SetJustifyH("LEFT")
    right:SetText(body)

    return math.max(left:GetStringHeight(), right:GetStringHeight())
end

-- Examples take Blizzard's own gold, the colour GameFontNormal draws in.
local function exampleLine(text)
    return "e.g.  " .. NORMAL_FONT_COLOR:WrapTextInColorCode(text)
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

-- Full-width secondary note, used for the closing combination example.
local function buildNote(content, y, width, text)
    local note = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    note:SetPoint("TOPLEFT", SECTION_INNER_PAD, -y)
    note:SetWidth(width - SECTION_INNER_PAD * 2)
    note:SetJustifyH("LEFT")
    note:SetText(text)
    return note:GetStringHeight()
end

-- One attic line, spanning the title's width so it clears the portrait on the left and ends where the title does. Word wrap is off, so the line can never grow past the attic into the inset.
local function buildAtticLine(panel, anchor, fontObject, text)
    local line = panel:CreateFontString(nil, "ARTWORK", fontObject)
    line:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -ATTIC_PAD)
    line:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -ATTIC_PAD)
    line:SetJustifyH("LEFT")
    line:SetWordWrap(false)
    line:SetText(text)
    return line
end

-- ScrollFrameTemplate hangs its MinimalScrollBar off the scroll frame's right edge at SCROLL_FRAME_SCROLL_BAR_OFFSET_LEFT, so the gutter reserves that offset plus the bar's own width and the inset padding, which keeps the bar inside the inset. Returns the scroll child and its width, fixed before any text wraps.
local function buildScroll(panel)
    local scroll = CreateFrame("ScrollFrame", nil, panel.Inset, "ScrollFrameTemplate")
    local gutter = SCROLL_FRAME_SCROLL_BAR_OFFSET_LEFT + scroll.ScrollBar:GetWidth() + INSET_PAD
    scroll:SetPoint("TOPLEFT", INSET_PAD, -INSET_PAD)
    scroll:SetPoint("BOTTOMRIGHT", -gutter, INSET_PAD)

    local content = CreateFrame("Frame", nil, scroll)
    scroll:SetScrollChild(content)
    local width = PANEL_WIDTH - PANEL_INSET_LEFT_OFFSET + PANEL_INSET_RIGHT_OFFSET - INSET_PAD - gutter
    content:SetWidth(width)
    return content, width
end

-- The three sections, then the combination example, stacked down the scroll child.
local function layoutContent(content, width)
    local function withExample(e) return e.desc .. "\n" .. exampleLine(e.eg) end
    local sections = {
        { label = "Commands", entries = COMMANDS, describe = withExample },
        { label = "Manage", entries = MANAGE, describe = withExample },
        { label = "Flags", entries = FLAGS, describe = function(e) return e.desc .. "  (" .. table.concat(e.on, ", ") .. ")\n" .. exampleLine(e.eg) end },
    }

    local y = SECTION_GAP
    for _, spec in ipairs(sections) do
        local section = layoutSection(content, width, spec.label, spec.entries, spec.describe)
        section:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
        section:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -y)
        y = y + section:GetHeight() + SECTION_GAP
    end

    y = y + buildNote(content, y, width, FOOTER)
    content:SetHeight(y + SECTION_INNER_PAD)
end

-- Blizzard's tool window: portrait, title bar, close button and inset come with ButtonFrameTemplate. Escape closes it through UISpecialFrames, never UIPanelWindows, so it never pushes other panels around.
local function buildPanel()
    local panel = CreateFrame("Frame", PANEL_NAME, UIParent, "ButtonFrameTemplate")
    panel:SetSize(PANEL_WIDTH, PANEL_HEIGHT)
    panel:SetPoint("CENTER")
    panel:SetPortraitToAsset(PANEL_ICON)
    panel:SetTitle("Super Social")
    panel:SetFrameStrata("HIGH")
    panel:SetToplevel(true)
    panel:SetClampedToScreen(true)
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
    tinsert(UISpecialFrames, PANEL_NAME)

    -- A reference with no actions, so the inset takes the button bar's space.
    ButtonFrameTemplate_HideButtonBar(panel)

    local intro = buildAtticLine(panel, panel.TitleContainer, "GameFontHighlight", INTRO)
    buildAtticLine(panel, intro, "GameFontDisableSmall", INTRO_HINT)
    layoutContent(buildScroll(panel))

    panel:Hide()
    return panel
end

local panel

-- Built lazily on first open so no frame exists before the player asks for it.
function ns.TogglePanel()
    panel = panel or buildPanel()
    panel:SetShown(not panel:IsShown())
end
