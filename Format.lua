local _, ns = ...

-- One place for every WhisperThemAll chat line, so whispered, skipped, and
-- cooldown messages all read with the same colours, layout, and spacing.

local PREFIX = "|cff66ccffWhisperThemAll|r"

local COLORS = {
    sent  = "ff5cd65c", -- green — whispers that went out
    skip  = "ffe06666", -- red   — recipients filtered out
    cool  = "ffe6a23c", -- amber — cooldown activity
    name  = "ffffd200", -- gold  — targeted player names
    muted = "ff9d9d9d", -- gray  — secondary detail
}

-- Wrap text in one of the shared status colours.
local function tint(key, text)
    return "|c" .. COLORS[key] .. text .. "|r"
end

-- Header line: addon tag plus a one-line summary of the action.
local function status(text)
    DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. "  " .. text)
end

-- Indented detail beneath a header, marked with a consistent bullet.
local function detail(text)
    DEFAULT_CHAT_FRAME:AddMessage("    " .. tint("muted", "•") .. " " .. text)
end

-- Class colour as a |cAARRGGBB string, or nil when the class is unknown.
local function classColor(classFile)
    local c = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
    if not c then return nil end
    if c.colorStr then return c.colorStr end
    return string.format("ff%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255)
end

-- A name in its class colour, falling back to gold when the class isn't
-- known (replies and auction sellers carry no class data).
local function className(value, classFile)
    local short = value:match("^([^-]+)") or value
    local hex = classColor(classFile)
    if hex then return "|c" .. hex .. short .. "|r" end
    return tint("name", short)
end

local function plural(n, singular, multiple)
    if n == 1 then return singular end
    return multiple
end

ns.tint = tint
ns.status = status
ns.detail = detail
ns.className = className
ns.plural = plural
