-- Join LFG channels to enable message broadcasting

local function joinLfgChannels()
	JoinChannelByName("World")
	JoinChannelByName("LookingForGroup")
end

local function broadcastMessage(message)
	SendChatMessage(message, "CHANNEL", nil, GetChannelName("World"))
	SendChatMessage(message, "CHANNEL", nil, GetChannelName("LookingForGroup"))
end

local function handleInput(message)
	if message and message ~= "" then
		joinLfgChannels()
		broadcastMessage(message)
	end
end

SLASH_LFG1 = "/lfg"
SlashCmdList["LFG"] = handleInput
