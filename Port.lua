local PREFIX = "|cffffff00[WhisperThemAll]:|r "
local WHO_COOLDOWN = 5.5

local lastWho = 0

local function sendPortWho(zone)
    lastWho = GetTime()
    local maxLevel = GetMaxPlayerLevel()
    if zone and zone ~= "" then
        C_FriendList.SendWho("z-" .. zone .. " c-warlock 20-" .. maxLevel)
    else
        C_FriendList.SendWho("c-mage 20-" .. maxLevel)
    end
end

local function findPort(zone)
    local remaining = WHO_COOLDOWN - (GetTime() - lastWho)
    if remaining > 0 then
        print(PREFIX .. string.format("/who on cooldown -- %.1fs remaining.", remaining))
        return
    end
    sendPortWho(zone)
end

SLASH_PORT1 = "/port"
SlashCmdList["PORT"] = findPort
