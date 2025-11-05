-- Display available commands on login and via slash command

local YELLOW_LIGHT_LUA = "|cFFFDE89B"
local WHITE_LUA = "|cFFFFFFFF"

local function showCommandIntroMsg()
	print(YELLOW_LIGHT_LUA .. "/chitchat" .. "|r" .. " for available commands.")
end

local loginEventFrame = CreateFrame("Frame")
loginEventFrame:RegisterEvent("PLAYER_LOGIN")
loginEventFrame:SetScript("OnEvent", showCommandIntroMsg)

local function showCommandListTooltip()
	local tooltip = _G["ChitChatCommandTooltip"] or CreateFrame("GameTooltip", "ChitChatCommandTooltip", UIParent, "GameTooltipTemplate")
	tooltip:ClearLines()
	tooltip:SetOwner(UIParent, "ANCHOR_NONE")
	tooltip:SetPoint("CENTER", UIParent, "CENTER")
	tooltip:SetMovable(true)
	tooltip:EnableMouse(true)
	tooltip:RegisterForDrag("LeftButton")
	tooltip:SetScript("OnDragStart", tooltip.StartMoving)
	tooltip:SetScript("OnDragStop", tooltip.StopMovingOrSizing)

	tooltip:AddLine(YELLOW_LIGHT_LUA .. "ChitChat Classic" .. "|r", 1, 1, 1, true)
	tooltip:AddLine(" ")

	tooltip:AddLine(YELLOW_LIGHT_LUA .. "Broadcasting & Scanning" .. "|r")
	tooltip:AddLine(YELLOW_LIGHT_LUA .. "/lfg MESSAGE" .. "|r" .. WHITE_LUA .. " Broadcast to World/LFG" .. "|r")
	tooltip:AddLine(YELLOW_LIGHT_LUA .. "/cs KEYWORD" .. "|r" .. WHITE_LUA .. " Monitor chat for keyword" .. "|r")
	tooltip:AddLine(YELLOW_LIGHT_LUA .. "/cs WORD AND WORD" .. "|r" .. WHITE_LUA .. " Search with AND logic" .. "|r")
	tooltip:AddLine(YELLOW_LIGHT_LUA .. "/cs WORD OR WORD" .. "|r" .. WHITE_LUA .. " Search with OR logic" .. "|r")
	tooltip:AddLine(YELLOW_LIGHT_LUA .. "/cs WORD NOT WORD" .. "|r" .. WHITE_LUA .. " Search with NOT logic" .. "|r")
	tooltip:AddLine(YELLOW_LIGHT_LUA .. "/cs" .. "|r" .. WHITE_LUA .. " Stop scanning" .. "|r")
	tooltip:AddLine(" ")

	tooltip:AddLine(YELLOW_LIGHT_LUA .. "Whisper Utilities" .. "|r")
	tooltip:AddLine(YELLOW_LIGHT_LUA .. "/wt MESSAGE" .. "|r" .. WHITE_LUA .. " Whisper current target" .. "|r")
	tooltip:AddLine(YELLOW_LIGHT_LUA .. "/wt+ MESSAGE" .. "|r" .. WHITE_LUA .. " Whisper target (no spam)" .. "|r")
	tooltip:AddLine(YELLOW_LIGHT_LUA .. "/ww MESSAGE" .. "|r" .. WHITE_LUA .. " Whisper all in /who list" .. "|r")
	tooltip:AddLine(YELLOW_LIGHT_LUA .. "/ww N MESSAGE" .. "|r" .. WHITE_LUA .. " Whisper first N players" .. "|r")
	tooltip:AddLine(YELLOW_LIGHT_LUA .. "/ww -CLASS MSG" .. "|r" .. WHITE_LUA .. " Exclude class from whispers" .. "|r")
	tooltip:AddLine(YELLOW_LIGHT_LUA .. "/ww+ MESSAGE" .. "|r" .. WHITE_LUA .. " Whisper with ignore list" .. "|r")
	tooltip:AddLine(YELLOW_LIGHT_LUA .. "/ww reset" .. "|r" .. WHITE_LUA .. " Clear whisper ignore list" .. "|r")
	tooltip:AddLine(" ")

	tooltip:AddLine(YELLOW_LIGHT_LUA .. "Reply to Whispers" .. "|r")
	tooltip:AddLine(YELLOW_LIGHT_LUA .. "/rr MESSAGE" .. "|r" .. WHITE_LUA .. " Reply to recent whispers" .. "|r")
	tooltip:AddLine(YELLOW_LIGHT_LUA .. "/rr N MESSAGE" .. "|r" .. WHITE_LUA .. " Reply to last N senders" .. "|r")
	tooltip:AddLine(YELLOW_LIGHT_LUA .. "/rr reset" .. "|r" .. WHITE_LUA .. " Reset reply tracking" .. "|r")
	tooltip:AddLine(" ")

	tooltip:AddLine(YELLOW_LIGHT_LUA .. "Port Finder" .. "|r")
	tooltip:AddLine(YELLOW_LIGHT_LUA .. "/port" .. "|r" .. WHITE_LUA .. " Find mages in current zone" .. "|r")
	tooltip:AddLine(YELLOW_LIGHT_LUA .. "/port ZONE" .. "|r" .. WHITE_LUA .. " Find warlocks in zone" .. "|r")

	tooltip:Show()

	local closeBtn = CreateFrame("Button", nil, tooltip, "UIPanelCloseButton")
	closeBtn:SetPoint("TOPRIGHT", tooltip, "TOPRIGHT")
	closeBtn:SetScript("OnClick", function()
		tooltip:Hide()
	end)
end

SLASH_CHITCHAT1 = "/chitchat"
SlashCmdList["CHITCHAT"] = function(msg)
	if msg == "" then
		showCommandListTooltip()
	end
end
