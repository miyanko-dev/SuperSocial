local _, ns = ...

-- Bulk whispers are spaced out so a big run stays under Blizzard's chat
-- throttle instead of silently dropping messages.
local INTERVAL = 0.25

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
    local item = table.remove(pending, 1)
    if not item then
        finish()
        return
    end
    SendChatMessage(item.text, "WHISPER", nil, item.target)
    sent = sent + 1
end

-- Queue a whisper: the first goes out immediately, the rest one per INTERVAL.
function ns.queueWhisper(text, target)
    pending[#pending + 1] = { text = text, target = target }
    if not ticker then
        sendNext()
        ticker = C_Timer.NewTicker(INTERVAL, sendNext)
    end
end

-- Abort the current run. Returns how many already went out and how many were
-- still waiting, so the caller can report what the stop actually caught.
function ns.cancelQueue()
    local doneSent = sent
    local dropped = #pending
    wipe(pending)
    if ticker then ticker:Cancel() end
    ticker = nil
    sent = 0
    return doneSent, dropped
end
