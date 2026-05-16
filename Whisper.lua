local PREFIX = "|cffffff00[WhisperThemAll]:|r "

local applyingColor = false
local ignorePanel

local function notify(msg)
    print(PREFIX .. msg)
end

local function playerKey()
    return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
end

local function loadIgnore()
    WhisperThemAllDB = WhisperThemAllDB or {}
    WhisperThemAllDB.ignoredByChar = WhisperThemAllDB.ignoredByChar or {}
    local key = playerKey()
    local bucket = WhisperThemAllDB.ignoredByChar[key] or {}
    WhisperThemAllDB.ignoredByChar[key] = bucket
    -- migrate the legacy account-wide list into the current character on first load
    if WhisperThemAllDB.ignored then
        for name in pairs(WhisperThemAllDB.ignored) do
            bucket[name] = true
        end
        WhisperThemAllDB.ignored = nil
    end
    return bucket
end

local function clearIgnore()
    local ignored = loadIgnore()
    if next(ignored) == nil then
        notify("Ignore list is already empty.")
        return
    end
    wipe(ignored)
    notify("Ignore list cleared.")
    if ignorePanel and ignorePanel:IsShown() then
        ignorePanel:Refresh()
    end
end

local function whisperTarget(text, remember)
    if not text or text == "" then
        notify("Usage: /wt MESSAGE")
        return
    end
    if not (UnitExists("target") and UnitIsPlayer("target")) then
        notify("No valid player target.")
        return
    end
    local name = UnitName("target")
    local ignored = remember and loadIgnore() or nil
    if ignored and ignored[name] then
        notify(name .. " already contacted.")
        return
    end
    SendChatMessage(text, "WHISPER", nil, name)
    if ignored then ignored[name] = true end
end

local function parseWhoInput(input)
    local tokens = {}
    for token in input:gmatch("%S+") do
        tokens[#tokens + 1] = token
    end

    local cursor = 1
    local limit
    local excludes = {}

    while tokens[cursor] and tokens[cursor]:sub(1, 1) == "-" and #tokens[cursor] > 1 do
        local val = tokens[cursor]:sub(2)
        if val:match("^%d+$") then
            limit = tonumber(val)
        else
            excludes[#excludes + 1] = val:lower()
        end
        cursor = cursor + 1
    end

    local words = {}
    for i = cursor, #tokens do
        words[#words + 1] = tokens[i]
    end
    return limit, excludes, table.concat(words, " ")
end

local function isFiltered(info, excludes)
    if #excludes == 0 then return false end
    local class = (info.classStr or ""):lower()
    local area = (info.area or ""):lower()
    local rawName = (info.fullName or ""):lower()
    local name = rawName:match("^([^-]+)") or rawName
    for _, filter in ipairs(excludes) do
        if filter == class then return true end
        if area ~= "" and area:find(filter, 1, true) then return true end
        if name ~= "" and name:find(filter, 1, true) then return true end
    end
    return false
end

local function whisperWho(input, remember)
    local limit, excludes, text = parseWhoInput(input or "")
    if text == "" then return end
    local count = C_FriendList.GetNumWhoResults()
    if count == 0 then
        notify("No /who results.")
        return
    end
    limit = limit or count
    local ignored = remember and loadIgnore() or nil
    local sent = 0
    for i = 1, count do
        if sent >= limit then break end
        local info = C_FriendList.GetWhoInfo(i)
        if info and info.fullName
            and not isFiltered(info, excludes)
            and not (ignored and ignored[info.fullName]) then
            SendChatMessage(text, "WHISPER", nil, info.fullName)
            if ignored then ignored[info.fullName] = true end
            sent = sent + 1
        end
    end
    if sent == 0 then
        notify("No recipients after filtering.")
    elseif sent == 1 then
        notify("Sent 1 whisper.")
    else
        notify(string.format("Sent %d whispers.", sent))
    end
end

local function collectAuctionSellers()
    local count = GetNumAuctionItems("list")
    if not count or count == 0 then return nil end
    local seen = {}
    local order = {}
    local me = UnitName("player")
    for i = 1, count do
        local _, _, _, _, _, _, _, _, _, _, _, _, _, owner, ownerFullName = GetAuctionItemInfo("list", i)
        local name = ownerFullName or owner
        if name and name ~= "" and name ~= me and not seen[name] then
            seen[name] = true
            order[#order + 1] = name
        end
    end
    return order
end

local function whisperSellers(text)
    if not text or text == "" then
        notify("Usage: /ws MESSAGE")
        return
    end
    if not AuctionFrame or not AuctionFrame:IsShown() then
        notify("Open the auction house Browse tab and run a search first.")
        return
    end
    local names = collectAuctionSellers()
    if not names or #names == 0 then
        notify("No auction results -- run a search on the Browse tab first.")
        return
    end
    for _, name in ipairs(names) do
        SendChatMessage(text, "WHISPER", nil, name)
    end
    notify(string.format("Sent %d whisper(s).", #names))
end

local function blendWhisperColors(_, event, arg1)
    if event == "UPDATE_CHAT_COLOR" and arg1 ~= "WHISPER" and arg1 ~= "WHISPER_INFORM" then
        return
    end
    if applyingColor then return end
    local outgoing = ChatTypeInfo["WHISPER_INFORM"]
    local incoming = ChatTypeInfo["WHISPER"]
    if not outgoing or not incoming then return end
    applyingColor = true
    incoming.r = outgoing.r + (1 - outgoing.r) * 0.5
    incoming.g = outgoing.g + (1 - outgoing.g) * 0.5
    incoming.b = outgoing.b + (1 - outgoing.b) * 0.5
    applyingColor = false
end

local colorWatch = CreateFrame("Frame")
colorWatch:RegisterEvent("PLAYER_ENTERING_WORLD")
colorWatch:RegisterEvent("UPDATE_CHAT_COLOR")
colorWatch:SetScript("OnEvent", blendWhisperColors)

local function buildIgnorePanel()
    local f = CreateFrame("Frame", "WhisperThemAllIgnorePanel", UIParent, "BackdropTemplate")
    f:SetSize(280, 360)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    if f.SetBackdrop then
        f:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        f:SetBackdropColor(0, 0, 0, 0.9)
    end

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)

    local title = f:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -12)
    title:SetText("Whisper Ignore List")

    local helper = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    helper:SetPoint("TOPLEFT", 12, -36)
    helper:SetPoint("TOPRIGHT", -12, -36)
    helper:SetJustifyH("LEFT")
    helper:SetWordWrap(true)
    helper:SetText("Names remembered by /wt+ and /ww+. Click x to remove.")

    local scroll = CreateFrame("ScrollFrame", "$parentScroll", f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 12, -72)
    scroll:SetPoint("BOTTOMRIGHT", -28, 44)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(240, 1)
    scroll:SetScrollChild(content)

    local rowPool = {}
    local rowsActive = {}

    local function releaseRows()
        for _, row in ipairs(rowsActive) do
            row:Hide()
            row:ClearAllPoints()
            rowPool[#rowPool + 1] = row
        end
        wipe(rowsActive)
    end

    local function acquireRow()
        local row = table.remove(rowPool)
        if row then
            row:Show()
            row.removeBtn:Show()
            return row
        end
        row = CreateFrame("Frame", nil, content)
        row:SetHeight(20)
        local name = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        name:SetPoint("LEFT", 4, 0)
        name:SetJustifyH("LEFT")
        row.name = name
        local rm = CreateFrame("Button", nil, row, "UIPanelCloseButton")
        rm:SetSize(20, 20)
        rm:SetPoint("RIGHT", 0, 0)
        row.removeBtn = rm
        return row
    end

    function f:Refresh()
        releaseRows()
        local ignored = loadIgnore()
        local sorted = {}
        for n in pairs(ignored) do sorted[#sorted + 1] = n end
        table.sort(sorted)
        local rowHeight = 22
        for i, n in ipairs(sorted) do
            local row = acquireRow()
            row:SetParent(content)
            row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(i - 1) * rowHeight)
            row:SetWidth(240)
            row.name:SetText(n)
            row.removeBtn:SetScript("OnClick", function()
                ignored[n] = nil
                f:Refresh()
            end)
            rowsActive[#rowsActive + 1] = row
        end
        if #sorted == 0 then
            local row = acquireRow()
            row:SetParent(content)
            row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
            row:SetWidth(240)
            row.name:SetText("(empty)")
            row.removeBtn:Hide()
            rowsActive[#rowsActive + 1] = row
        end
        content:SetHeight(math.max(#sorted, 1) * rowHeight)
    end

    local clearBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    clearBtn:SetSize(80, 22)
    clearBtn:SetPoint("BOTTOMLEFT", 12, 12)
    clearBtn:SetText("Clear All")
    clearBtn:SetScript("OnClick", function() clearIgnore() end)

    local closeBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    closeBtn:SetSize(80, 22)
    closeBtn:SetPoint("BOTTOMRIGHT", -12, 12)
    closeBtn:SetText("Close")
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    tinsert(UISpecialFrames, "WhisperThemAllIgnorePanel")
    f:Hide()
    f:SetScript("OnShow", function(self) self:Refresh() end)
    return f
end

local function toggleIgnorePanel()
    if not ignorePanel then ignorePanel = buildIgnorePanel() end
    if ignorePanel:IsShown() then ignorePanel:Hide() else ignorePanel:Show() end
end

SLASH_WHISPERTARGET1 = "/wt"
SlashCmdList["WHISPERTARGET"] = function(text) whisperTarget(text or "", false) end

SLASH_WHISPERTARGETPLUS1 = "/wt+"
SlashCmdList["WHISPERTARGETPLUS"] = function(text) whisperTarget(text, true) end

SLASH_WHISPERWHO1 = "/ww"
SlashCmdList["WHISPERWHO"] = function(input) whisperWho(input, false) end

SLASH_WHISPERWHOPLUS1 = "/ww+"
SlashCmdList["WHISPERWHOPLUS"] = function(input) whisperWho(input, true) end

SLASH_WHISPERSELLERS1 = "/ws"
SlashCmdList["WHISPERSELLERS"] = whisperSellers

_G.WhisperThemAll = _G.WhisperThemAll or {}
WhisperThemAll.ClearIgnore = clearIgnore
WhisperThemAll.ToggleIgnorePanel = toggleIgnorePanel
