local YELLOW = "|cffffff00"
local RESET = "|r"

local RAID_ICONS = {
    star = 1, circle = 2, diamond = 3, triangle = 4,
    moon = 5, square = 6, cross = 7, skull = 8,
}

local scanExpr = {}
local scanFrame = CreateFrame("Frame")

local function renderIcons(text)
    return text:gsub("{(.-)}", function(symbol)
        local index = RAID_ICONS[strlower(symbol)]
        if index then
            return "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_" .. index .. ":0|t"
        end
        return "{" .. symbol .. "}"
    end)
end

local function notifyMatch(msg, sender)
    local link = "|Hplayer:" .. sender .. "|h" .. YELLOW .. "[" .. sender .. "]:" .. RESET .. "|h"
    print(link .. " " .. renderIcons(msg))
    PlaySound(3175, "Master", true)
end

local function matchesExpr(text)
    local lower = strlower(text)

    local function contains(keyword)
        return strfind(lower, strlower(keyword), 1, true)
    end

    if not scanExpr.operator then
        return contains(scanExpr.operands[1])
    elseif scanExpr.operator == "AND" then
        return contains(scanExpr.operands[1]) and contains(scanExpr.operands[2])
    elseif scanExpr.operator == "OR" then
        return contains(scanExpr.operands[1]) or contains(scanExpr.operands[2])
    elseif scanExpr.operator == "NOT" then
        if #scanExpr.operands == 2 then
            return contains(scanExpr.operands[1]) and not contains(scanExpr.operands[2])
        else
            return not contains(scanExpr.operands[1])
        end
    end

    return false
end

scanFrame:SetScript("OnEvent", function(_, _, msg, sender, _, channel)
    if scanExpr.operands and #scanExpr.operands > 0 and strmatch(channel, "%d+") then
        local num = tonumber(strmatch(channel, "%d+"))
        if num and num >= 1 and num <= 20 and matchesExpr(msg) then
            notifyMatch(msg, sender)
        end
    end
end)

local function parseExpr(input)
    local tokens = {}
    for token in string.gmatch(input, "%S+") do
        tokens[#tokens + 1] = token
    end

    if #tokens == 0 then
        return { operator = nil, operands = {} }
    elseif #tokens == 1 then
        return { operator = nil, operands = { tokens[1] } }
    end

    local operands = {}
    local operator = nil
    local i = 1

    while i <= #tokens do
        local upper = string.upper(tokens[i])
        if upper == "AND" or upper == "OR" or upper == "NOT" then
            if not operator then
                operator = upper
            end
        else
            operands[#operands + 1] = tokens[i]
        end
        i = i + 1
    end

    return { operator = operator, operands = operands }
end

SLASH_CHATSCAN1 = "/cs"
SlashCmdList["CHATSCAN"] = function(input)
    input = input:match("^%s*(.-)%s*$")

    if input == "" then
        scanExpr = {}
        scanFrame:UnregisterEvent("CHAT_MSG_CHANNEL")
        print(YELLOW .. "[ChitChat]:" .. RESET .. " scan disabled.")
    else
        scanExpr = parseExpr(input)
        if not scanFrame:IsEventRegistered("CHAT_MSG_CHANNEL") then
            scanFrame:RegisterEvent("CHAT_MSG_CHANNEL")
        end
        print(YELLOW .. "[ChitChat]:" .. RESET .. " scanning for " .. input)
    end
end
