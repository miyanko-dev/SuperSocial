local _, ns = ...

-- The outgoing commands: /ww blasts the current or a fresh /who list, /wt whispers the selected player, and /ws whispers the sellers of the auction house listing on screen. All hand every whisper to the queue.

local ok = ns.Ok
local fail = ns.Fail
local note = ns.Note
local plural = ns.Plural
local trim = ns.Trim
local parseDuration = ns.ParseDuration
local DURATION_HINT = ns.DurationHint
local refuseRestricted = ns.RefuseRestricted

local function whisperTarget(input)
    input = trim(input)
    local tokens = {}
    for t in input:gmatch("%S+") do tokens[#tokens + 1] = t end
    local cursor = 1
    local cooldownSeconds
    if tokens[cursor] == "-cd" then
        cooldownSeconds = tokens[cursor + 1] and parseDuration(tokens[cursor + 1])
        if not cooldownSeconds then
            fail("-cd needs a duration.", DURATION_HINT)
            return
        end
        cursor = cursor + 2
    end
    local parts = ns.SplitWhisper(table.concat(tokens, " ", cursor))
    if #parts == 0 then
        note("Usage: /wt MESSAGE whispers your target, e.g. /wt got room for one more? Add -cd 30d to put them on cooldown.")
        return
    end
    if refuseRestricted() then return end
    if not (UnitExists("target") and UnitIsPlayer("target")) then
        fail("No target selected.", "Pick a player first.")
        return
    end

    -- Built the way Blizzard's own whisper menu builds it: the target keeps its surname, or every namesake with another surname could hear it.
    local targetName, hidden = ns.UnitFullName("target")
    if hidden then
        fail("Target name hidden.", "This map keeps player names from addons.")
        return
    end
    if not targetName then
        fail("No target selected.", "Pick a player first.")
        return
    end
    if ns.IsBlocked(ns.LoadBlocked(), targetName) then
        -- The slash command takes one token, so a "First Surname" is offered in its hyphen spelling.
        local typed = targetName:gsub("%s+", "-")
        fail("Blocked.", targetName .. " is on the block list (/ss -unblock " .. typed .. ").")
        return
    end

    -- Through the queue for cap rescue, flagged personal so /rr treats it as an answer, not a blast.
    for _, part in ipairs(parts) do
        ns.QueueWhisper(part, targetName, "personal")
    end
    if cooldownSeconds then
        ns.LoadCooldowns()[ns.NameKey(targetName)] = time() + cooldownSeconds
        ok("Whispered", targetName .. ", " .. ns.FormatDuration(cooldownSeconds) .. " cooldown.")
    else
        ok("Whispered", targetName .. ".")
    end
end

-- Load the lists a blast reads and writes, once per command.
local function loadLists(opts)
    local lists = { blocked = ns.LoadBlocked() }
    if opts.useCooldown then
        lists.cooldown = ns.LoadCooldowns()
        lists.cooldownSeconds = opts.cooldownSeconds
    end
    return lists
end

-- Cap to -limit, report one status line, queue the sends, stamp the persistent lists and hand the names to /rr.
local function sendBlast(opts, lists, eligible, counts, total, singular, multiple)
    local sendCount = opts.limit and math.min(opts.limit, #eligible) or #eligible
    counts.limit = #eligible - sendCount
    local pool = total .. " " .. plural(total, singular, multiple)

    if sendCount == 0 then
        fail("Nobody to whisper.", "None of " .. pool .. " qualify.")
        ns.SkipLine(counts, total)
        return
    end

    -- One fact per line, in the order they matter: who hears it, who doesn't and why, what the lists recorded, then the message itself. The queue's counter picks up from there.
    local eta = ns.SendEta(sendCount * #ns.SplitWhisper(opts.text))
    local tail = eta and (", " .. eta) or ""
    -- The cooldown rides on the opening line rather than taking one of its own: it is a property of this run, not an event in it.
    if lists.cooldownSeconds then tail = tail .. ", " .. ns.Tint("cool", ns.FormatDuration(lists.cooldownSeconds) .. " cooldown") end
    ok("Whispering", (sendCount == total and "all " or sendCount .. " of ") .. pool .. tail .. ".")
    ns.SkipLine(counts, total - sendCount)
    ns.QuoteMessage(opts.text)

    local sentNames = {}
    for i = 1, sendCount do
        local name = eligible[i]
        ns.QueueWhisper(opts.text, name)
        sentNames[#sentNames + 1] = name
        -- Only a timed -cd records new recipients; bare -cd just reads the list.
        if lists.cooldown and lists.cooldownSeconds then lists.cooldown[ns.NameKey(name)] = time() + lists.cooldownSeconds end
    end

    -- /rr replies to these names once they whisper back.
    ns.TrackWhispered(sentNames)
end

local function dispatchWho(opts)
    -- The who list is RequiresFriendList, which returns nothing while the friend list is unavailable.
    local count = C_FriendList.GetNumWhoResults() or 0
    if count == 0 then
        fail("No /who results.", "Run /who first, or use -who (…).")
        return
    end

    local groupSet = ns.BuildGroupSet()
    local lists = loadLists(opts)

    -- Keys are the ones ns.SkipLine reads, counted in the order the checks run.
    local counts = { blocked = 0, cooldown = 0, filter = 0, group = 0, recentGroup = 0 }
    local eligible = {}
    for i = 1, count do
        local whoInfo = C_FriendList.GetWhoInfo(i)
        local fullName = whoInfo and whoInfo.fullName
        if fullName then
            if ns.InGroup(groupSet, fullName) then
                counts.group = counts.group + 1
            elseif ns.WasRecentlyGrouped(fullName) then
                counts.recentGroup = counts.recentGroup + 1
            elseif ns.IsBlocked(lists.blocked, fullName) then
                counts.blocked = counts.blocked + 1
            elseif ns.IsFiltered(whoInfo, opts.terms) or not ns.IsIncluded(whoInfo, opts.includeTerms) then
                counts.filter = counts.filter + 1
            elseif lists.cooldown and ns.OnCooldown(lists.cooldown, fullName) then
                counts.cooldown = counts.cooldown + 1
            else
                eligible[#eligible + 1] = fullName
            end
        end
    end

    sendBlast(opts, lists, eligible, counts, count, "/who result", "/who results")
end

local WHO_TIMEOUT = 6      -- Seconds to wait for the server's answer before aborting, since the who list still holds the previous search.
local PANEL_RESTORE = 8    -- The server answers some queries seconds late; re-arming the panel too early lets a straggler pop it open.

-- The Group Finder's Who tab is the only WHO_LIST_UPDATE listener, and an update can pop its window open (WhoList.lua UpdateWhoList). It is load-on-demand, so it is looked up per run. Restore wakes it only when the addon took its event away, never when it was not listening.
local deafened

local function deafenWhoUi()
    local panel = LFGWhoListFrame
    if panel and panel:IsEventRegistered("WHO_LIST_UPDATE") then
        panel:UnregisterEvent("WHO_LIST_UPDATE")
        deafened = panel
    end
    C_FriendList.SetWhoToUi(true)
end

-- Put the who plumbing back where the panel expects it: results to chat unless the panel is open, and the panel listening again. IsVisible, because the tab keeps its own shown flag when the Group Finder closes around it, and its OnHide has already sent results back to chat.
local function restoreWhoUi()
    C_FriendList.SetWhoToUi(LFGWhoListFrame ~= nil and LFGWhoListFrame:IsVisible())
    if deafened then deafened:RegisterEvent("WHO_LIST_UPDATE") end
    deafened = nil
end

-- One waiter for every -who run, because frames are never collected and a fresh one per run would leak. The run counter lets a stale timeout recognise that a newer run owns the frame.
local whoWaiter = CreateFrame("Frame")
local whoRun = 0

-- -who runs the search itself: results go to the API list instead of chat, the who panel is deafened so it can't pop open, and the blast waits for this query's own results. A timeout aborts rather than dispatching, because the who list still holds the previous search and whispering those people would be the wrong run.
local function runWho(opts)
    deafenWhoUi()

    whoRun = whoRun + 1
    local run = whoRun
    local function live()
        return run == whoRun and whoWaiter:IsEventRegistered("WHO_LIST_UPDATE")
    end
    local function stop()
        whoWaiter:UnregisterEvent("WHO_LIST_UPDATE")
        whoWaiter:SetScript("OnEvent", nil)
    end

    whoWaiter:RegisterEvent("WHO_LIST_UPDATE")
    -- A /who fires WHO_LIST_UPDATE twice: once to clear the old rows, then again when the server's answer lands. Only the second one carries results.
    whoWaiter:SetScript("OnEvent", function()
        local count, total = C_FriendList.GetNumWhoResults()
        if not count or count == 0 then return end
        stop()
        if total and total > count then
            note(count .. " of " .. total .. " matches shown. Narrow the filter for the rest.")
        end
        dispatchWho(opts)
    end)

    C_Timer.After(WHO_TIMEOUT, function()
        if not live() then return end
        stop()
        fail("Nobody found.", "\"" .. opts.who .. "\" came back empty or /who is throttled. Retry in a few seconds.")
    end)
    -- Restore on a fixed clock rather than on completion, because a straggling answer after the timeout would otherwise pop the panel. A newer run owns the plumbing by then, so this one leaves it alone or it would route that run's results back to chat.
    C_Timer.After(PANEL_RESTORE, function()
        if run ~= whoRun then return end
        restoreWhoUi()
    end)

    C_FriendList.SendWho(opts.who)
end

local function whisperWho(input)
    local opts = ns.ParseFlags(trim(input))
    if ns.FlagMistake(opts, true) then return end
    if not opts.text or opts.text == "" then
        note("Usage: /ww MESSAGE whispers your /who results, e.g. /ww LFM SM live. /ss lists every flag.")
        return
    end
    if refuseRestricted() then return end
    if opts.who then
        runWho(opts)
    else
        dispatchWho(opts)
    end
end

-- Every seller of the listing once, in listing order, minus yourself. The results already name you "player"; the name check also catches a listing that spells you out.
local function uniqueSellers(sellers)
    local me = ns.UnitFullName("player")
    local seen, names = {}, {}
    for _, name in ipairs(sellers) do
        local key = ns.NameKey(name)
        if key and not seen[key] and not ns.SameName(name, me) then
            seen[key] = true
            names[#names + 1] = name
        end
    end
    return names
end

-- One hint per reason no listing can be read, naming the one step that is missing.
local LISTING_HINTS = {
    closed = { "Auction house closed.", "Open it, then open an item's listings." },
    browse = { "No item listings open.", "Browse rows name no sellers. Open an item's listings first." },
}

local function whisperSellers(input)
    local opts = ns.ParseFlags(trim(input))
    if ns.FlagMistake(opts, true) then return end
    if ns.UsedWho(opts) then
        fail("-who doesn't apply to /ws.", "It reads the auction house listings.")
        return
    end

    -- Sellers carry no class or zone, so the term filters can't apply here.
    if #opts.terms > 0 or #opts.includeTerms > 0 then
        fail("-skip and -only don't apply to /ws.", "Sellers carry no class or zone.")
        return
    end
    if not opts.text or opts.text == "" then
        note("Usage: /ws MESSAGE whispers every seller in the item listings open in the auction house, e.g. /ws still selling your Black Lotus?")
        return
    end
    if refuseRestricted() then return end
    local problem = ns.ListingProblem()
    if problem then
        fail(LISTING_HINTS[problem][1], LISTING_HINTS[problem][2])
        return
    end
    local sellers, unnamed = ns.ListingSellers()
    if unnamed > 0 then
        note("Up to " .. unnamed .. " " .. plural(unnamed, "seller", "sellers") .. " unnamed by the auction house, not whispered.")
    end
    local names = uniqueSellers(sellers)
    if #names == 0 then
        fail("No other sellers", "in the open listings.")
        return
    end

    local lists = loadLists(opts)
    local counts = { blocked = 0, cooldown = 0 }
    local eligible = {}
    for _, sellerName in ipairs(names) do
        if ns.IsBlocked(lists.blocked, sellerName) then
            counts.blocked = counts.blocked + 1
        elseif lists.cooldown and ns.OnCooldown(lists.cooldown, sellerName) then
            counts.cooldown = counts.cooldown + 1
        else
            eligible[#eligible + 1] = sellerName
        end
    end

    local item = ns.ListingItem()
    local of = item and (" of " .. item) or ""
    sendBlast(opts, lists, eligible, counts, #names, "seller" .. of, "sellers" .. of)
end

SLASH_WHISPERTARGET1 = "/wt"
SlashCmdList["WHISPERTARGET"] = whisperTarget

SLASH_WHISPERWHO1 = "/ww"
SlashCmdList["WHISPERWHO"] = whisperWho

SLASH_WHISPERSELLERS1 = "/ws"
SlashCmdList["WHISPERSELLERS"] = whisperSellers
