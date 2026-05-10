local function findPort(zone)
    local maxLevel = GetMaxPlayerLevel()

    if zone ~= "" then
        C_FriendList.SendWho("z-" .. zone .. " c-warlock 20-" .. maxLevel)
    else
        C_FriendList.SendWho("z-" .. GetRealZoneText() .. " c-mage 40-" .. maxLevel)
    end
end

SLASH_PORT1 = "/port"
SlashCmdList["PORT"] = findPort
