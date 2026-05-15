local PREFIX = "|cffffff00[WhisperThemAll]:|r "
local WHO_COOLDOWN = 5.5

local lastAnnounce = 0
local tickTimers = {}

local function cancelTicks()
    for i = #tickTimers, 1, -1 do
        local t = tickTimers[i]
        if t and not t:IsCancelled() then t:Cancel() end
        tickTimers[i] = nil
    end
end

local function scheduleTicks(remaining)
    for n = 1, 3 do
        local at = remaining - n
        if at > 0 then
            tickTimers[#tickTimers + 1] = C_Timer.NewTimer(at, function()
                print(PREFIX .. string.format("/who in %ds...", n))
            end)
        end
    end
    tickTimers[#tickTimers + 1] = C_Timer.NewTimer(remaining, function()
        print(PREFIX .. "/who ready -- send it now.")
    end)
end

local function announcePort()
    local now = GetTime()
    local remaining = WHO_COOLDOWN - (now - lastAnnounce)
    if remaining > 0 then
        print(PREFIX .. string.format("/who on cooldown -- %.1fs remaining.", remaining))
        return
    end
    lastAnnounce = now
    cancelTicks()
    print(PREFIX .. string.format("/who window started -- ready in %.1fs.", WHO_COOLDOWN))
    scheduleTicks(WHO_COOLDOWN)
end

SLASH_PORT1 = "/port"
SlashCmdList["PORT"] = announcePort
