local _, ns = ...

-- One place for every WhisperThemAll chat line, so whispered, skipped, and
-- cooldown messages all read with the same colours, layout, and spacing.

local PREFIX = "|cff66ccffWhisper Them All|r"

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

-- One status line per event: the addon tag in brackets, then the whole summary,
-- written to read like a quick note from a whisper assistant. Everything stays
-- on a single line, with no bullets and no detail block.
local function status(text)
    DEFAULT_CHAT_FRAME:AddMessage("[" .. PREFIX .. "]: " .. text)
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
    add(counts.skiplist, "skip", "on the skip list")
    add(counts.cooldown, "cool", "on cooldown")
    add(counts.filter, nil, "filtered out")
    add(counts.group, nil, "in your group")
    add(counts.limit, nil, "over the limit")
    if #parts == 0 then return nil end
    return table.concat(parts, ", ")
end

-- Inline summary of what a send recorded to the persistent lists (or would,
-- under -p). Returns a comma-joined fragment, or nil when neither -skip nor a
-- timed -cd applied, so the caller can append it to the one status line.
local function appliedSummary(count, addedToSkip, cooldownMinutes, isPreview)
    local parts = {}
    if addedToSkip then
        local lead = isPreview and "would add " or "added "
        parts[#parts + 1] = tint("skip", lead .. count .. " to skip list")
    end
    if cooldownMinutes then
        local lead = isPreview and ("would put " .. count) or count
        parts[#parts + 1] = tint("cool", lead .. " on cooldown for " .. cooldownMinutes .. " min")
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
