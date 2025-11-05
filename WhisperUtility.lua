-- Whisper utility functions for target and who list messaging with spam protection

local YELLOW_LIGHT_LUA = "|cFFFDE89B"
local WHITE_LUA = "|cFFFFFFFF"

local function initIgnoreList()
	if not ChitChatClassicDB then
		ChitChatClassicDB = {}
	end
	if type(ChitChatClassicDB.MultiWhisperIgnore) ~= "table" then
		ChitChatClassicDB.MultiWhisperIgnore = {}
	end
end

local function sendTargetWhisper(messageText)
	if not messageText or messageText == "" then
		print(YELLOW_LIGHT_LUA .. "[ChitChat]: " .. WHITE_LUA .. "Usage: /wt MESSAGE")
		return
	end
	if UnitExists("target") and UnitIsPlayer("target") then
		local targetName = UnitName("target")
		SendChatMessage(messageText, "WHISPER", nil, targetName)
	else
		print(YELLOW_LIGHT_LUA .. "[ChitChat]: " .. WHITE_LUA .. "No valid player target selected")
	end
end

local function sendTargetWhisperProtected(messageText)
	if not messageText or messageText == "" then
		print(YELLOW_LIGHT_LUA .. "[ChitChat]: " .. WHITE_LUA .. "Usage: /wt+ MESSAGE")
		return
	end
	if UnitExists("target") and UnitIsPlayer("target") then
		local targetName = UnitName("target")
		initIgnoreList()
		if not ChitChatClassicDB.MultiWhisperIgnore[targetName] then
			SendChatMessage(messageText, "WHISPER", nil, targetName)
			ChitChatClassicDB.MultiWhisperIgnore[targetName] = true
		else
			print(YELLOW_LIGHT_LUA .. "[ChitChat]: " .. WHITE_LUA .. "Player " .. targetName .. " already contacted")
		end
	else
		print(YELLOW_LIGHT_LUA .. "[ChitChat]: " .. WHITE_LUA .. "No valid player target selected")
	end
end

local function getWhisperParams(commandString)
	local playerLimit, skipClass, messageText

	playerLimit, skipClass, messageText = commandString:match("^(%d+)%s+%-(%w+)%s+(.+)$")
	if playerLimit then
		return playerLimit, skipClass, messageText
	end

	playerLimit, messageText = commandString:match("^(%d+)%s+(.+)$")
	if playerLimit then
		return playerLimit, nil, messageText
	end

	skipClass, messageText = commandString:match("^%-(%w+)%s+(.+)$")
	if skipClass then
		return nil, skipClass, messageText
	end

	return nil, nil, commandString
end

local function sendWhoWhisper(commandString)
	local playerLimit, skipClass, messageText = getWhisperParams(commandString)
	local whoCount = C_FriendList.GetNumWhoResults()
	playerLimit = playerLimit and tonumber(playerLimit) or whoCount
	skipClass = skipClass and skipClass:lower() or nil
	if messageText and messageText ~= "" and whoCount and whoCount > 0 then
		local sentCount = 0
		for i = 1, whoCount do
			if sentCount >= playerLimit then break end
			local info = C_FriendList.GetWhoInfo(i)
			if info and info.fullName then
				if not skipClass or info.classStr:lower() ~= skipClass then
					SendChatMessage(messageText, "WHISPER", nil, info.fullName)
					sentCount = sentCount + 1
				end
			end
		end
	end
end

local function sendWhoWhisperSkip(commandString)
	initIgnoreList()
	local playerLimit, skipClass, messageText = getWhisperParams(commandString)
	local whoCount = C_FriendList.GetNumWhoResults()
	playerLimit = playerLimit and tonumber(playerLimit) or whoCount
	skipClass = skipClass and skipClass:lower() or nil
	if messageText and messageText ~= "" and whoCount and whoCount > 0 then
		local sentCount = 0
		for i = 1, whoCount do
			if sentCount >= playerLimit then break end
			local info = C_FriendList.GetWhoInfo(i)
			if info and info.fullName then
				local playerKey = info.fullName
				if (not skipClass or info.classStr:lower() ~= skipClass) and not ChitChatClassicDB.MultiWhisperIgnore[playerKey] then
					SendChatMessage(messageText, "WHISPER", nil, info.fullName)
					ChitChatClassicDB.MultiWhisperIgnore[playerKey] = true
					sentCount = sentCount + 1
				end
			end
		end
	end
end

local function resetIgnoreList()
	if ChitChatClassicDB and ChitChatClassicDB.MultiWhisperIgnore then
		ChitChatClassicDB.MultiWhisperIgnore = {}
		print(YELLOW_LIGHT_LUA .. "[ChitChat]: " .. WHITE_LUA .. "MultiWhisper ignore list cleared.")
	else
		print(YELLOW_LIGHT_LUA .. "[ChitChat]: " .. WHITE_LUA .. "MultiWhisper ignore list is already empty.")
	end
end

SLASH_WHISPERTARGET1 = "/wt"
SlashCmdList["WHISPERTARGET"] = sendTargetWhisper

SLASH_WHISPERTARGET_SKIP1 = "/wt+"
SlashCmdList["WHISPERTARGET_SKIP"] = sendTargetWhisperProtected

SLASH_WHISPERWHO1 = "/ww"
SlashCmdList["WHISPERWHO"] = sendWhoWhisper

SLASH_WHISPERWHO_SKIP1 = "/ww+"
SlashCmdList["WHISPERWHO_SKIP"] = sendWhoWhisperSkip

SLASH_WHISPER_RESET1 = "/ww reset"
SlashCmdList["WHISPER_RESET"] = resetIgnoreList
