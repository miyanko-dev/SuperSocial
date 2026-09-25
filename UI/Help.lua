local _, ns = ...

-- A scrollable reference panel for every command and option, opened with "/ss". Built entirely from the game's own templates and font objects, each defined per client, so it wears Era's or Forever's own chrome, scroll bar and type instead of assuming a texture path exists on both.

local PANEL_WIDTH = 480
local PANEL_HEIGHT = 580
local INSET_MARGINS = 4 + 6    -- BasicFrameTemplateWithInset's InsetBg sits 4px in on the left and 6px on the right, on both clients
local INSET_PAD = 8            -- content sits this far inside that well, which also keeps Era's scroll bar (drawn 7px above the frame, Classic/ScrollDefine.lua) inside it
local SCROLLBAR_GUTTER = 28    -- ScrollFrameTemplate hangs its bar off the frame's right edge: 8px wide at +6 on Forever (MinimalScrollBar), 25px at -2 on Era (WowClassicScrollBar)
local SECTION_GAP = 26         -- also clears the section label riding above each box
local SECTION_INNER_PAD = 12
local SECTION_LABEL_LIFT = 7
local LABEL_WIDTH = 116
local COLUMN_GAP = 12
local ROW_GAP = 10

-- /ws only exists where the Era auction house still names sellers (Core/Compat.lua), so the reference names it only there.
local function available(command)
    return command ~= "/ws" or ns.AuctionSellers ~= nil
end

local function commandList(commands)
    local shown = {}
    for _, command in ipairs(commands) do
        if available(command) then shown[#shown + 1] = command end
    end
    return table.concat(shown, ", ")
end

-- The panel is three sections: the slash commands, the /ss management subcommands, then the flags that refine /ww. "cmd" is the yellow left-column label; "eg" carries the full worked example so the column stays scannable.
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
        desc = "Whisper every seller on the auction house Browse page.",
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

-- Bordered section container, the game's own inset box, with its yellow label riding on the top edge.
local function buildSection(parent, labelText)
    local section = CreateFrame("Frame", nil, parent, "InsetFrameTemplate")

    local label = section:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("BOTTOMLEFT", section, "TOPLEFT", 4, SECTION_LABEL_LIFT)
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
        if available(entry.cmd) then
            y = y + buildRow(section, y, width, entry.cmd, describe(entry)) + ROW_GAP
        end
    end
    section:SetHeight(y - ROW_GAP + SECTION_INNER_PAD)
    return section
end

-- Full-width white note, used for the intro and the closing combination example.
local function buildNote(content, y, width, text)
    local note = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    note:SetPoint("TOPLEFT", SECTION_INNER_PAD, -y)
    note:SetWidth(width - SECTION_INNER_PAD * 2)
    note:SetJustifyH("LEFT")
    note:SetText(text)
    return note:GetStringHeight()
end

local helpFrame

local function buildFrame()
    -- The game's own titled window: title bar, borders, close button and content inset come with the template, which each client defines in its own UIPanelTemplates.xml.
    local panel = CreateFrame("Frame", "SuperSocialHelpFrame", UIParent, "BasicFrameTemplateWithInset")
    panel:SetSize(PANEL_WIDTH, PANEL_HEIGHT)
    panel:SetPoint("CENTER")
    panel:SetFrameStrata("DIALOG")
    panel:SetToplevel(true)
    panel:SetClampedToScreen(true)
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
    panel.TitleText:SetText("Super Social")
    tinsert(UISpecialFrames, "SuperSocialHelpFrame")

    -- ScrollFrameTemplate builds SCROLL_FRAME_SCROLL_BAR_TEMPLATE, which each client's ScrollDefine.lua names, so the bar is Blizzard's current one on both instead of the legacy UIPanelScrollFrame art.
    local scroll = CreateFrame("ScrollFrame", "SuperSocialHelpScroll", panel, "ScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", panel.InsetBg, "TOPLEFT", INSET_PAD, -INSET_PAD)
    scroll:SetPoint("BOTTOMRIGHT", panel.InsetBg, "BOTTOMRIGHT", -SCROLLBAR_GUTTER, INSET_PAD)

    -- The scroll child needs its width before any text wraps, and the template's fixed inset margins make it computable up front.
    local content = CreateFrame("Frame", nil, scroll)
    scroll:SetScrollChild(content)
    local width = PANEL_WIDTH - INSET_MARGINS - INSET_PAD - SCROLLBAR_GUTTER
    content:SetWidth(width)

    local y = 4
    y = y + buildNote(content, y, width, INTRO) + SECTION_GAP

    local function withExample(e) return e.desc .. "\n" .. exampleLine(e.eg) end

    local sections = {
        { label = "Commands", entries = COMMANDS, describe = withExample },
        { label = "Manage", entries = MANAGE, describe = withExample },
        { label = "Flags", entries = FLAGS, describe = function(e) return e.desc .. "  (" .. commandList(e.on) .. ")\n" .. exampleLine(e.eg) end },
    }
    for _, spec in ipairs(sections) do
        local section = layoutSection(content, width, spec.label, spec.entries, spec.describe)
        section:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
        section:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -y)
        y = y + section:GetHeight() + SECTION_GAP
    end

    y = y + buildNote(content, y, width, FOOTER)
    content:SetHeight(y + SECTION_INNER_PAD)

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
