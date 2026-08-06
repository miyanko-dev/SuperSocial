local addonName, ns = ...

-- LibDBIcon minimap button: left-click toggles the command reference panel. The icon position persists in the saved variables like every other setting.

local MINIMAP_DEFAULT_POS = 200
local YELLOW = "|cffffd200"

local function setupMinimapButton()
    local LDB = LibStub and LibStub:GetLibrary("LibDataBroker-1.1", true)
    local LDBIcon = LibStub and LibStub:GetLibrary("LibDBIcon-1.0", true)
    if not (LDB and LDBIcon) or LDBIcon:IsRegistered(addonName) then return end

    local dataObject = LDB:NewDataObject(addonName, {
        type = "launcher",
        text = "Whisper Them All",
        icon = 134149,
        OnClick = function(_, button)
            if button == "LeftButton" then
                ns.ToggleHelp()
            end
        end,
        OnTooltipShow = function(tt)
            tt:AddLine("Whisper Them All")
            tt:AddLine(YELLOW .. "Left-click|r to toggle the command reference.", 1, 1, 1)
            tt:AddLine(YELLOW .. "/ww MESSAGE|r whispers everyone in your /who results.", 1, 1, 1)
        end,
    })

    LDBIcon:Register(addonName, dataObject, WhisperThemAllDB.minimap)
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(self, event, name)
    if event == "ADDON_LOADED" and name == addonName then
        WhisperThemAllDB = WhisperThemAllDB or {}
        if type(WhisperThemAllDB.minimap) ~= "table" then
            WhisperThemAllDB.minimap = { hide = false, minimapPos = MINIMAP_DEFAULT_POS }
        end
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        setupMinimapButton()
        self:UnregisterEvent("PLAYER_LOGIN")
    end
end)
