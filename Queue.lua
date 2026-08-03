local _, ns = ...

-- Bulk whispers are spaced out so a big run stays under Blizzard's whisper throttle instead of dropping messages and spamming "you can't message that player right now" errors.
local INTERVAL = 0.5

local pending = {}
local ticker
local sent = 0

local function finish()
    if ticker then ticker:Cancel() end
    ticker = nil
    sent = 0
end

-- Send the next queued whisper, stopping the ticker once the queue is empty.
local function sendNext()
    local nextWhisper = table.remove(pending, 1)
    if not nextWhisper then
        finish()
        return
    end
    -- Flag the send as a blast so the reply tracker won't mistake its INFORM event for a personal answer.
    ns.MarkBlastWhisper(nextWhisper.target)
    SendChatMessage(nextWhisper.text, "WHISPER", nil, nextWhisper.target)
    sent = sent + 1
end

-- Split a message on ";" into separate whispers, dropping empty parts.
function ns.SplitWhisper(text)
    local parts = {}
    for piece in (text or ""):gmatch("[^;]+") do
        local part = piece:gsub("^%s+", ""):gsub("%s+$", "")
        if part ~= "" then parts[#parts + 1] = part end
    end
    return parts
end

-- Queue a whisper: the first goes out immediately, the rest one per INTERVAL. A ";" in the text queues each part as its own whisper, back to back.
function ns.QueueWhisper(text, target)
    for _, part in ipairs(ns.SplitWhisper(text)) do
        pending[#pending + 1] = { text = part, target = target }
    end
    if not ticker then
        sendNext()
        ticker = C_Timer.NewTicker(INTERVAL, sendNext)
    end
end

-- Abort the current run. Returns how many already went out and how many were still waiting, so the caller can report what the stop actually caught.
function ns.CancelQueue()
    local doneSent = sent
    local dropped = #pending
    wipe(pending)
    if ticker then ticker:Cancel() end
    ticker = nil
    sent = 0
    return doneSent, dropped
end
