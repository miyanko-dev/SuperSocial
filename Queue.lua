local _, ns = ...

-- Bulk whispers are spaced out so a big run stays under Blizzard's chat
-- throttle instead of silently dropping messages.
local INTERVAL = 0.5

local pending = {}
local ticker
local processed = 0
local nounSingular = "whisper"
local nounPlural = "whispers"

local function sendNext()
    local item = table.remove(pending, 1)
    if not item then
        if ticker then ticker:Cancel() end
        ticker = nil
        if processed > 0 then
            ns.status(ns.tint("sent", "All " .. processed .. " " .. ns.plural(processed, nounSingular, nounPlural) .. " sent") .. ".")
        end
        processed = 0
        return
    end
    SendChatMessage(item.text, "WHISPER", nil, item.target)
    processed = processed + 1
end

-- Queue a whisper: the first goes out immediately, the rest one per INTERVAL.
-- singular/plural name the run in the completion line ("replies" for /rr).
function ns.queueWhisper(text, target, singular, plural)
    pending[#pending + 1] = { text = text, target = target }
    if not ticker then
        nounSingular = singular or "whisper"
        nounPlural = plural or "whispers"
        sendNext()
        ticker = C_Timer.NewTicker(INTERVAL, sendNext)
    end
end

-- Abort the current run. Returns how many already went out and how many were
-- still waiting, so the caller can report what the stop actually caught.
function ns.cancelQueue()
    local sent = processed
    local dropped = #pending
    wipe(pending)
    if ticker then ticker:Cancel() end
    ticker = nil
    processed = 0
    return sent, dropped
end
