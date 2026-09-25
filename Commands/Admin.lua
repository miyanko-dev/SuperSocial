local _, ns = ...

-- /ss: the reference panel and every list, rate and run management subcommand.

local ok = ns.Ok
local fail = ns.Fail
local note = ns.Note
local plural = ns.Plural
local trim = ns.Trim
local loadBlocked = ns.LoadBlocked
local loadCooldowns = ns.LoadCooldowns
local parseDuration = ns.ParseDuration
local DURATION_HINT = ns.DurationHint

-- Display form with a leading capital, matching how names render in game.
local function displayName(name)
    return name:sub(1, 1):upper() .. name:sub(2)
end

local function listBlocked()
    local names = {}
    for _, shown in pairs(loadBlocked()) do
        names[#names + 1] = shown
    end
    if #names == 0 then
        note("Block list is empty.")
        return
    end
    table.sort(names)
    note(#names .. " blocked: " .. table.concat(names, ", ") .. ".")
end

-- One token per name, so a surname or realm rides on a hyphen and never reads as a second name.
local function blockName(name)
    if name:find("%s") then
        fail("One name at a time.", "Join a surname or realm with a hyphen, e.g. /ss -block Thrall-Stormborn.")
        return
    end
    local blocked = loadBlocked()
    local key = ns.NameKey(name)
    if not key then
        fail("Not a name.", "e.g. /ss -block Thrall.")
        return
    end
    if blocked[key] then
        note(blocked[key] .. " is already blocked.")
        return
    end
    blocked[key] = displayName(name)
    ok("Blocked", blocked[key] .. ". /ss -unblock " .. blocked[key] .. " undoes it.")
end

local function unblockName(name)
    local blocked = loadBlocked()
    local key = ns.NameKey(name)
    local shown = key and blocked[key]
    if not shown then
        note(displayName(name) .. " isn't on the block list.")
        return
    end
    blocked[key] = nil
    ok("Unblocked", shown .. ".")
end

local MANUAL_COOLDOWN = 30 * 86400 -- /ss -cd NAME without a duration: the long memory the old ignore list gave.

-- Put one player on cooldown by hand, the same list -cd sends build.
local function cooldownName(arg)
    local name, duration, extra = arg:match("^(%S+)%s*(%S*)%s*(.*)$")
    if extra ~= "" then
        fail("One name, then an optional duration.", "e.g. /ss -cd Thrall 30d.")
        return
    end
    local seconds = MANUAL_COOLDOWN
    if duration ~= "" then
        seconds = parseDuration(duration)
        if not seconds then
            fail("-cd needs a duration.", "\"" .. duration .. "\" isn't one. " .. DURATION_HINT)
            return
        end
    end
    local key = ns.NameKey(name)
    if not key then
        fail("Not a name.", "e.g. /ss -cd Thrall 30d.")
        return
    end
    loadCooldowns()[key] = time() + seconds
    ok("On cooldown", displayName(name) .. ", " .. ns.FormatDuration(seconds) .. ".")
end

-- The cooldown list runs into the thousands, so its size and its longest remaining wait are the two facts worth knowing before deciding whether to clear it.
local function cooldownStatus()
    local cooldowns = loadCooldowns()
    local now = time()
    local count, longest = 0, 0
    for _, expiry in pairs(cooldowns) do
        count = count + 1
        if expiry - now > longest then longest = expiry - now end
    end
    if count == 0 then
        note("Nobody is on cooldown.")
        return
    end
    note(count .. " on cooldown, longest " .. ns.FormatRemaining(longest) .. " left. /ss -cd clear empties it.")
end

local function quietCommand(arg)
    local target
    if arg == "" then
        target = not ns.QuietBlasts()
    elseif arg == "on" then
        target = true
    elseif arg == "off" then
        target = false
    else
        note("Usage: /ss quiet toggles the counter, /ss quiet on and /ss quiet off set it.")
        return
    end
    ns.SetQuietBlasts(target)
    if target then
        ok("Quiet mode on.", "Runs show one counter instead of every whisper.")
    else
        ok("Quiet mode off.", "Every whisper prints again.")
    end
end

local function adminCommand(input)
    -- Keep the raw form so block/unblock names keep their capitalization.
    local raw = trim(input)
    input = raw:lower()
    if input == "" or input == "help" then
        ns.ToggleHelp()
    elseif input == "-block" or input == "-block list" then
        listBlocked()
    elseif input:match("^%-block%s") then
        blockName(trim(raw:match("^%S+%s+(.*)$")))
    elseif input == "-unblock" then
        note("Usage: /ss -unblock NAME.")
    elseif input:match("^%-unblock%s") then
        unblockName(trim(raw:match("^%S+%s+(.*)$")))
    elseif input == "-cd" then
        cooldownStatus()
    elseif input == "-cd clear" then
        ns.ClearCooldowns()
        ok("Cooldown list cleared.")
    elseif input:match("^%-cd%s") then
        cooldownName(trim(raw:match("^%S+%s+(.*)$")))
    elseif input:match("^%-ignore") then
        -- The old command still gets a pointer, so muscle memory lands somewhere useful.
        note("-ignore is now -cd 30d. /ss -cd manages the list.")
    elseif input == "quiet" then
        quietCommand("")
    elseif input:match("^quiet%s") then
        quietCommand(trim(input:match("^%S+%s+(.*)$")))
    elseif input == "rate" then
        note("Send rate " .. string.format("%.2f", ns.PacingRate()) .. "/s, learned from the server. /ss rate reset restores the default.")
    elseif input == "rate reset" then
        ok("Rate reset.", string.format("%.2f", ns.ResetPacingRate()) .. "/s until the server teaches otherwise.")
    elseif input == "stop" then
        local sent, dropped = ns.CancelQueue()
        if sent == 0 and dropped == 0 then
            fail("Nothing to stop.", "No whispers are queued.")
        else
            ok("Stopped.", sent .. " sent, " .. dropped .. " " .. plural(dropped, "whisper", "whispers") .. " cancelled.")
        end
    else
        fail("Unknown command", "\"" .. raw .. "\". /ss opens the reference.")
    end
end

SLASH_SUPERSOCIAL1 = "/ss"
SlashCmdList["SUPERSOCIAL"] = adminCommand
