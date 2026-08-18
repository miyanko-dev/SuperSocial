local _, ns = ...

-- One place for every Super Social chat line: a yellow prefix, plain white text, and three status colours for the lead word of each message.
local COLORS = {
    sent = "ff40ff40", -- green — positive: whispers sent, actions completed
    skip = "ffff4040", -- red   — negative: errors, skips, empty results
    cool = "ff76c8ff", -- blue  — cooldown info
}

-- Wrap text in one of the shared status colours.
local function tint(key, text)
    return "|c" .. COLORS[key] .. text .. "|r"
end

-- One status line per event: the addon tag, then the whole summary. Inline status colours in `text` carry their own codes and show through.
local function status(text)
    DEFAULT_CHAT_FRAME:AddMessage("|cffffff00[Super Social]:|r " .. text)
end

-- Every confirmation line is a colour-tinted lead phrase plus optional plain detail, so the shape and colour-by-meaning stay identical everywhere. Callers pick a builder by intent instead of assembling colours by hand.
local function report(colorKey, lead, detail)
    local head = tint(colorKey, lead)
    if detail and detail ~= "" then
        head = head .. " " .. detail
    end
    status(head)
end

-- ok: an action completed. fail: it couldn't, or nothing matched. note: a neutral state readout or usage line, left plain.
local function ok(lead, detail) report("sent", lead, detail) end
local function fail(lead, detail) report("skip", lead, detail) end
local function note(text) status(text) end

local function plural(n, singular, multiple)
    if n == 1 then return singular end
    return multiple
end

-- Turn a count-by-reason table into the "why they were skipped" line, listing only the non-zero reasons in a fixed order. Skip-list and cooldown counts carry their status colour so they stand out at a glance.
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
    add(counts.recentGroup, nil, "recently in your group")
    add(counts.limit, nil, "over the limit")
    if #parts == 0 then return nil end
    return table.concat(parts, ", ")
end

-- Inline summary of what a send recorded to the persistent lists. Returns a comma-joined fragment, or nil when neither -ignore nor a timed -cd applied, so the caller can append it to the one status line.
local function appliedSummary(count, addedToSkip, cooldownMinutes)
    local parts = {}
    if addedToSkip then
        parts[#parts + 1] = "added " .. count .. " to ignore list"
    end
    if cooldownMinutes then
        parts[#parts + 1] = tint("cool", count .. " on cooldown for " .. cooldownMinutes .. " min")
    end
    if #parts == 0 then return nil end
    return table.concat(parts, ", ")
end

ns.Tint = tint
ns.Status = status
ns.Ok = ok
ns.Fail = fail
ns.Note = note
ns.Plural = plural
ns.SkipBreakdown = skipBreakdown
ns.AppliedSummary = appliedSummary
