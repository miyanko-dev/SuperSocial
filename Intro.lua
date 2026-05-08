local YELLOW = "|cFFFDE89B"
local RESET  = "|r"

local function printCommands()
	print(YELLOW .. "[/cs KEYWORD]" .. RESET .. ": Monitor chat for a keyword")
	print(YELLOW .. "[/cs WORD AND WORD]" .. RESET .. ": Match both words")
	print(YELLOW .. "[/cs WORD OR WORD]" .. RESET .. ": Match either word")
	print(YELLOW .. "[/cs WORD NOT WORD]" .. RESET .. ": Match first, exclude second")
	print(YELLOW .. "[/cs]" .. RESET .. ": Stop scanning")
	print(YELLOW .. "[/wt MESSAGE]" .. RESET .. ": Whisper your current target")
	print(YELLOW .. "[/wt-once MESSAGE]" .. RESET .. ": Whisper target (one-time only)")
	print(YELLOW .. "[/ww MESSAGE]" .. RESET .. ": Whisper everyone in /who results")
	print(YELLOW .. "[/ww N MESSAGE]" .. RESET .. ": Whisper first N players in /who results")
	print(YELLOW .. "[/ww -CLASS MESSAGE]" .. RESET .. ": Whisper /who results, excluding a class")
	print(YELLOW .. "[/ww-once MESSAGE]" .. RESET .. ": Whisper /who results (one-time only)")
	print(YELLOW .. "[/ww reset]" .. RESET .. ": Clear the persistent ignore list")
	print(YELLOW .. "[/rr MESSAGE]" .. RESET .. ": Reply to all recent whisperers")
	print(YELLOW .. "[/rr N MESSAGE]" .. RESET .. ": Reply to the last N whisperers")
	print(YELLOW .. "[/rr reset]" .. RESET .. ": Clear the session reply list")
	print(YELLOW .. "[/port]" .. RESET .. ": Find mages in your current zone")
	print(YELLOW .. "[/port ZONE]" .. RESET .. ": Find warlocks in the specified zone")
end

local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", function()
	print(YELLOW .. "ChitChat Classic loaded." .. RESET .. " Type /chitchat for commands.")
end)

SLASH_CHITCHAT1 = "/chitchat"
SlashCmdList["CHITCHAT"] = function(msg)
	printCommands()
end
