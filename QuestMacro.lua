local _, ns = ...

-- Shift-clicking a quest in the Questie tracker pastes its link into the open macro body, mirroring the paste Questie already does into an open chat box.

local fail = ns.Fail

-- The macro body only exists once Blizzard_MacroUI has loaded and a macro is selected.
local function macroBody()
    if MacroFrameText and MacroFrameText:IsVisible() then return MacroFrameText end
end

-- Chat keeps first claim on the click, so an open edit box still receives the link.
local function chatWaiting()
    if ChatFrameUtil and ChatFrameUtil.GetActiveWindow then return ChatFrameUtil.GetActiveWindow() end
    return ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow()
end

local function showsLevel()
    return Questie and Questie.db and Questie.db.profile and Questie.db.profile.trackerShowQuestLevel
end

-- Build the same text Questie inserts into chat, so both destinations read identically. Questie's builder reads its own database, so fall back to the plain name if that query comes up empty.
local function questText(quest)
    if showsLevel() then
        local ok, text = pcall(function()
            return QuestieLoader:ImportModule("QuestieLink"):GetQuestLinkStringById(quest.Id)
        end)
        if ok and text then return text end
    end
    return "[" .. quest.name .. " (" .. quest.Id .. ")]"
end

-- Count bytes against the letter limit, because that never underestimates and the edit box truncates silently.
local function roomFor(body, text)
    return body:GetNumLetters() + #text <= body:GetMaxLetters()
end

local function pasteQuest(quest)
    local body = macroBody()
    if not body then return false end

    local text = questText(quest)
    if not text or text == "" then return false end

    if not roomFor(body, text) then
        fail("Macro is full.", "That quest link needs more than the "
            .. (body:GetMaxLetters() - body:GetNumLetters()) .. " characters left in this macro.")
        return true
    end

    -- Focus first so the link lands at the cursor the user left in the body.
    body:SetFocus()
    body:Insert(text)
    return true
end

-- Claim the click only for a shift-left on a quest line with a macro waiting for text.
local function claims(line, button)
    if button ~= "LeftButton" then return false end
    if not IsModifiedClick("CHATLINK") then return false end
    if chatWaiting() then return false end
    if not (line.Quest and line.Quest.Id) then return false end
    return pasteQuest(line.Quest)
end

local wrappers = {}
local ours = {}

-- One wrapper per Questie handler, so re-wrapping on every tracker rebuild allocates nothing.
local function wrapHandler(handler)
    if not wrappers[handler] then
        local wrapper = function(line, button)
            if claims(line, button) then return end
            handler(line, button)
        end
        wrappers[handler] = wrapper
        ours[wrapper] = true
    end
    return wrappers[handler]
end

local hookedLines = {}

-- Questie re-assigns OnClick on every tracker rebuild, so wrap its setter instead of the script.
local function hookLine(line)
    if hookedLines[line] then return end
    hookedLines[line] = true

    local setOnClick = line.SetOnClick
    line.SetOnClick = function(self, mode)
        setOnClick(self, mode)

        -- Achievement lines keep Questie's own behavior, because their id is not a quest.
        if mode ~= "quest" then return end

        local handler = self:GetScript("OnClick")
        if handler and not ours[handler] then
            self:SetScript("OnClick", wrapHandler(handler))
        end
    end
end

-- Wrap the line factory at Questie's load, well before its init coroutine fills the pool.
EventUtil.ContinueOnAddOnLoaded("Questie", function()
    if not QuestieLoader then return end

    local trackerLine = QuestieLoader:ImportModule("TrackerLine")
    if not trackerLine.New then return end

    local new = trackerLine.New
    trackerLine.New = function(...)
        local line = new(...)
        hookLine(line)
        return line
    end
end)
