local _, ns = ...

-- Bulk whispers are spaced out so a big run stays under Blizzard's chat
-- throttle instead of silently dropping messages.
local INTERVAL = 0.5

local pending = {}
local ticker
local processed = 0

local function sendNext()
    local item = table.remove(pending, 1)
    if not item then
        if ticker then ticker:Cancel() end
        ticker = nil
        if processed > 0 then
            ns.status(ns.tint("sent", "All " .. processed .. " " .. ns.plural(processed, "whisper", "whispers") .. " sent") .. ".")
        end
        processed = 0
        return
    end
    SendChatMessage(item.text, "WHISPER", nil, item.target)
    processed = processed + 1
end

-- Queue a whisper: the first goes out immediately, the rest one per INTERVAL.
function ns.queueWhisper(text, target)
    pending[#pending + 1] = { text = text, target = target }
    if not ticker then
        sendNext()
        ticker = C_Timer.NewTicker(INTERVAL, sendNext)
    end
end
