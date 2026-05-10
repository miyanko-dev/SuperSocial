local YELLOW = "|cffffff00"
local RESET = "|r"

local function printHelp()
    print(YELLOW .. "[ChitChat]:" .. RESET .. " commands:")
    print("  /cs KEYWORD            scan chat for a keyword")
    print("  /cs WORD AND WORD      match both words")
    print("  /cs WORD OR WORD       match either word")
    print("  /cs WORD NOT WORD      match first, exclude second")
    print("  /cs                    stop scanning")
    print("  /wt MESSAGE            whisper your current target")
    print("  /wt-once MESSAGE       whisper target (one-time only)")
    print("  /ww MESSAGE            whisper everyone in /who results")
    print("  /ww N MESSAGE          whisper first N players in /who results")
    print("  /ww -CLASS MESSAGE     whisper /who results, excluding a class")
    print("  /ww-once MESSAGE       whisper /who results (one-time only)")
    print("  /ww reset              clear the persistent ignore list")
    print("  /rr MESSAGE            reply to all recent whisperers")
    print("  /rr N MESSAGE          reply to the last N whisperers")
    print("  /rr reset              clear the session reply list")
    print("  /port                  find mages in your current zone")
    print("  /port ZONE             find warlocks in the specified zone")
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function()
    print(YELLOW .. "[ChitChat]:" .. RESET .. " loaded. Type /chitchat for commands.")
end)

SLASH_CHITCHAT1 = "/chitchat"
SlashCmdList["CHITCHAT"] = printHelp
