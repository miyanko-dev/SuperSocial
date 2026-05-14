local PREFIX = "|cffffff00[WhisperThemAll]:|r "
local WHO_COOLDOWN = 5.5

local lastWho = 0
local pendingTimer
local pendingZone

local function sendPortWho(zone)
    lastWho = GetTime()
    local maxLevel = GetMaxPlayerLevel()
    if zone and zone ~= "" then
        C_FriendList.SendWho("z-" .. zone .. " c-warlock 20-" .. maxLevel)
    else
        C_FriendList.SendWho("z-" .. GetRealZoneText() .. " c-mage 40-" .. maxLevel)
    end
end

local function findPort(zone)
    local remaining = WHO_COOLDOWN - (GetTime() - lastWho)
    if remaining > 0 then
        pendingZone = zone
        if pendingTimer then
            print(PREFIX .. string.format("Replaced queued /port (%.1fs remaining).", remaining))
            return
        end
        print(PREFIX .. string.format("Queued /port -- sending in %.1fs.", remaining))
        pendingTimer = C_Timer.NewTimer(remaining, function()
            local zoneToSend = pendingZone
            pendingTimer = nil
            pendingZone = nil
            sendPortWho(zoneToSend)
        end)
        return
    end
    sendPortWho(zone)
end

SLASH_PORT1 = "/port"
SlashCmdList["PORT"] = findPort
