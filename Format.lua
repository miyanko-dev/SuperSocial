local _, ns = ...

-- One place for every Super Social chat line, and one colour convention for the whole addon:
--   yellow  the [Super Social] tag, nothing else
--   green   what went out, and actions that completed
--   red     what didn't go out, and everyone excluded
--   blue    list bookkeeping: cooldowns, the whisper cap
-- A line colours its lead token only and leaves the body white, so the eye lands on the same spot every time. The single exception is a line reporting a mix of outcomes, where each count takes its own colour.
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

-- Name the message a run is about to send, once, because the per-whisper lines that used to show it are muted. A ";" message names each part in the order it goes out.
local function quoteMessage(text)
    local quoted = {}
    for _, part in ipairs(ns.SplitWhisper(text)) do
        quoted[#quoted + 1] = "\"" .. part .. "\""
    end
    if #quoted == 0 then return end
    report("sent", "Sending:", table.concat(quoted, " then "))
end

local function plural(n, singular, multiple)
    if n == 1 then return singular end
    return multiple
end

-- Every non-zero skip reason in a fixed order, as one plain phrase. The line's lead carries the colour, so the reasons read in a single weight instead of a stripe of competing ones.
local function skipReasons(counts)
    local parts = {}
    local function add(n, label)
        if n and n > 0 then parts[#parts + 1] = n .. " " .. label end
    end
    add(counts.blocked, "blocked")
    add(counts.cooldown, "on cooldown")
    add(counts.filter, "filtered")
    add(counts.group, "in your group")
    add(counts.recentGroup, "recently grouped")
    add(counts.limit, "over the limit")
    if #parts == 0 then return nil end
    return table.concat(parts, ", ")
end

-- Who the run left out and why, on its own line. Silent when nobody was skipped.
local function skipLine(counts, skipped)
    if not skipped or skipped <= 0 then return end
    local why = skipReasons(counts)
    if why then
        report("skip", "Skipped " .. skipped .. ":", why .. ".")
    else
        report("skip", "Skipped " .. skipped .. ".")
    end
end

-- A duration in the largest unit that divides it evenly, so 30d reads back as "30 d" and 90 minutes as "90 min" rather than "1.5 h".
local function formatDuration(seconds)
    if seconds % 86400 == 0 then return math.floor(seconds / 86400) .. " d" end
    if seconds % 3600 == 0 then return math.floor(seconds / 3600) .. " h" end
    if seconds % 60 == 0 then return math.floor(seconds / 60) .. " min" end
    return seconds .. " s"
end

-- A remaining wait rounded up to its largest unit, for status lines where "29 d" says more than the exact second count.
local function formatRemaining(seconds)
    if seconds >= 86400 then return math.ceil(seconds / 86400) .. " d" end
    if seconds >= 3600 then return math.ceil(seconds / 3600) .. " h" end
    if seconds >= 60 then return math.ceil(seconds / 60) .. " min" end
    return math.max(seconds, 0) .. " s"
end

ns.Tint = tint
ns.Status = status
ns.Ok = ok
ns.Fail = fail
ns.Note = note
ns.QuoteMessage = quoteMessage
ns.Plural = plural
ns.SkipReasons = skipReasons
ns.SkipLine = skipLine
ns.FormatDuration = formatDuration
ns.FormatRemaining = formatRemaining
