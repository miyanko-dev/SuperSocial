local PREFIX = "|cffffff00[WhisperThemAll]:|r "
local YELLOW = "|cffffff00"
local RESET = "|r"

local function line(command, text)
    print(YELLOW .. "[" .. command .. "]:" .. RESET .. " " .. text)
end

local function printHelp()
    print(PREFIX .. "commands:")
    line("/cs", "open the chat scan panel")
    line("/cs start", "start scanning with saved settings")
    line("/cs stop", "stop the active scan")
    line("/wt MESSAGE", "whisper your current target")
    line("/wt+ MESSAGE", "whisper target and remember")
    line("/ww MESSAGE", "whisper everyone in /who results")
    line("/ww N MESSAGE", "whisper first N players in /who results")
    line("/ww N -FILTER... MSG", "exclude players matching any class or zone filter")
    line("/ww+ ... MESSAGE", "whisper /who results and remember")
    line("/w-clear", "clear the remembered whisper list")
    line("/ws MESSAGE", "whisper every seller in the open auction house")
    line("/rr MESSAGE", "reply to all recent whisperers")
    line("/rr N MESSAGE", "reply to the last N whisperers")
    line("/rr reset", "clear the session reply list")
    line("/port", "find mages in your current zone")
    line("/port ZONE", "find warlocks in the specified zone")
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function()
    print(PREFIX .. "loaded. Type /whisperthemall for commands.")
end)

SLASH_WHISPERTHEMALL1 = "/whisperthemall"
SlashCmdList["WHISPERTHEMALL"] = printHelp
