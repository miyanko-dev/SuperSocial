-- Track recent whisper players and handle multi-reply functionality

local YELLOW_LIGHT_LUA = "|cFFFDE89B"
local WHITE_LUA = "|cFFFFFFFF"

local recentWhisperList = {}
local recentWhisperSet = {}
local alreadyWhisperedSet = {}
local maxRecentWhisper = 80

local function sendToLastWhisperers(inputText)
	local targetCount, messageText = inputText:match("^(%d+)%s+(.+)$")
	if not messageText then
		messageText = inputText
		targetCount = #recentWhisperList
	else
		targetCount = tonumber(targetCount)
	end
	if #recentWhisperList == 0 then
		print(YELLOW_LIGHT_LUA .. "[ChitChat]: " .. WHITE_LUA .. "No players have whispered you yet.")
		return
	end
	if targetCount and messageText and messageText ~= "" then
		local sessionSet = {}
		local startIdx = math.max(#recentWhisperList - targetCount + 1, 1)
		for i = startIdx, #recentWhisperList do
			local playerName = recentWhisperList[i]
			if playerName and not sessionSet[playerName] and not alreadyWhisperedSet[playerName] then
				SendChatMessage(messageText, "WHISPER", nil, playerName)
				sessionSet[playerName] = true
				alreadyWhisperedSet[playerName] = true
			end
		end
	else
		print(YELLOW_LIGHT_LUA .. "[ChitChat]: " .. WHITE_LUA .. "Usage: /rr MESSAGE or /rr N MESSAGE")
	end
end

local function addRecentWhisper(playerName)
	if recentWhisperSet[playerName] then
		for i = 1, #recentWhisperList do
			if recentWhisperList[i] == playerName then
				table.remove(recentWhisperList, i)
				break
			end
		end
	else
		recentWhisperSet[playerName] = true
	end
	table.insert(recentWhisperList, playerName)
	while #recentWhisperList > maxRecentWhisper do
		local removedName = table.remove(recentWhisperList, 1)
		recentWhisperSet[removedName] = nil
	end
end

local whisperFrame = CreateFrame("Frame")
whisperFrame:RegisterEvent("CHAT_MSG_WHISPER")
whisperFrame:SetScript("OnEvent", function(_, _, _, senderName)
	addRecentWhisper(senderName)
end)

SLASH_REPLYRECENT1 = "/rr"
SlashCmdList["REPLYRECENT"] = function(inputText)
	if inputText == "reset" then
		alreadyWhisperedSet = {}
		print(YELLOW_LIGHT_LUA .. "[ChitChat]: " .. WHITE_LUA .. "Reset whispered players list. You can now whisper all recent players again.")
	else
		sendToLastWhisperers(inputText)
	end
end
