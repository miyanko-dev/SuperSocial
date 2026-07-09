local _, ns = ...

-- One place for every WhisperThemAll chat line, so whispered, skipped, and
-- cooldown messages all read with the same colours, layout, and spacing.

-- The tag shown on every status line, coloured to match incoming whispers so
-- the addon's notes sit alongside your whisper conversation.
local SENDER = "Whisper Them All"

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

-- Hex of the incoming whisper colour, so the [Whisper Them All] tag matches the
-- whispers it sits beside. Read at print time to track any recolour.
local function whisperHex()
    local c = (ChatTypeInfo and ChatTypeInfo.WHISPER) or { r = 1, g = 0.5, b = 1 }
    return string.format("ff%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255)
end

-- One status line per event: a [Whisper Them All] tag in the incoming whisper
-- colour, then the whole summary. Inline semantic colours in `text` carry their
-- own and show through.
local function status(text)
    DEFAULT_CHAT_FRAME:AddMessage("|c" .. whisperHex() .. "[" .. SENDER .. "]|r: " .. text)
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

-- Turn a count-by-reason table into the "why they were skipped" line, listing
-- only the non-zero reasons in a fixed order. Skip-list and cooldown counts
-- carry their status colour so they stand out at a glance.
local function skipBreakdown(counts)
    local parts = {}
    local function add(n, colorKey, label)
        if n and n > 0 then
            local head = colorKey and tint(colorKey, tostring(n)) or tostring(n)
            parts[#parts + 1] = head .. " " .. label
        end
    end
    add(counts.blocked, "skip", "blocked")
    add(counts.skiplist, "skip", "on the ignore list")
    add(counts.cooldown, "cool", "on cooldown")
    add(counts.filter, nil, "filtered out")
    add(counts.group, nil, "in your group")
    add(counts.limit, nil, "over the limit")
    if #parts == 0 then return nil end
    return table.concat(parts, ", ")
end

-- Inline summary of what a send recorded to the persistent lists. Returns a
-- comma-joined fragment, or nil when neither -ignore nor a timed -cd applied, so
-- the caller can append it to the one status line.
local function appliedSummary(count, addedToSkip, cooldownMinutes)
    local parts = {}
    if addedToSkip then
        parts[#parts + 1] = tint("skip", "added " .. count .. " to ignore list")
    end
    if cooldownMinutes then
        parts[#parts + 1] = tint("cool", count .. " on cooldown for " .. cooldownMinutes .. " min")
    end
    if #parts == 0 then return nil end
    return table.concat(parts, ", ")
end

ns.tint = tint
ns.status = status
ns.className = className
ns.plural = plural
ns.skipBreakdown = skipBreakdown
ns.appliedSummary = appliedSummary
