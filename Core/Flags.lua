local _, ns = ...

-- Command input: trimming, the flag grammar /ww and /rr share, and the term matching -skip and -only apply to /who rows.

local fail = ns.Fail
local parseDuration = ns.ParseDuration
local DURATION_HINT = ns.DurationHint

local function trim(s)
    return (s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

-- Every flag parseFlags understands, used to catch one misplaced after the message.
local FLAG_WORDS = { ["-limit"] = true, ["-skip"] = true, ["-only"] = true, ["-cd"] = true, ["-who"] = true }

-- Flags whose value is a bracket group, mapped to the opts field the group fills.
local BRACKET_FLAGS = { ["-who"] = "who", ["-skip"] = "terms", ["-only"] = "includeTerms" }

-- A bracket flag may arrive glued to its opening bracket, so "-skip(mage)" still names the flag.
local function flagName(token)
    return token:match("^(%-%a+)%(") or token
end

-- A bracket group starts right after its flag and runs to the first closing bracket, so the message may start with anything and the boundary is never guessed. Text glued behind the closing bracket becomes the next token. Returns the content and the cursor past it, or nil, the mistake and the cursor.
local function readBracket(tokens, cursor, flag)
    local head = tokens[cursor]:sub(#flag + 1)
    if head == "" then
        cursor = cursor + 1
        head = tokens[cursor]
    end
    if not head or head:sub(1, 1) ~= "(" then return nil, "open", cursor end
    local parts = {}
    local piece = head:sub(2)
    while true do
        local body, rest = piece:match("^(.-)%)(.*)$")
        if body then
            parts[#parts + 1] = body
            if rest ~= "" then tokens[cursor] = rest else cursor = cursor + 1 end
            local content = trim(table.concat(parts, " "))
            if content == "" then return nil, "empty", cursor end
            return content, nil, cursor
        end
        parts[#parts + 1] = piece
        cursor = cursor + 1
        piece = tokens[cursor]
        if not piece then return nil, "close", cursor end
    end
end

-- Field keys inside -skip and -only brackets, the same letters /who uses so one vocabulary serves both.
local TERM_FIELDS = { c = "class", z = "zone", n = "name" }

-- Split a bracket group into terms: a word or a quoted phrase, optionally led by c- z- n- to pin it to one field. Without a key a term matches any field.
local function splitTerms(content)
    local terms = {}
    local rest = content
    while true do
        rest = rest:match("^%s*(.*)$")
        if rest == "" then break end
        local key = rest:match("^([cznCZN])%-")
        if key then rest = rest:sub(3) end
        local text
        if rest:sub(1, 1) == '"' then
            local close = rest:find('"', 2, true)
            text = rest:sub(2, (close or #rest + 1) - 1)
            rest = close and rest:sub(close + 1) or ""
        else
            text = rest:match("^%S*")
            rest = rest:sub(#text + 1)
        end
        text = trim(text):lower()
        if text ~= "" then
            terms[#terms + 1] = { field = key and TERM_FIELDS[key:lower()], text = text }
        end
    end
    return terms
end

local function parseFlags(input)
    local tokens = {}
    for t in input:gmatch("%S+") do tokens[#tokens + 1] = t end
    local cursor = 1
    local opts = { terms = {}, includeTerms = {} }
    while cursor <= #tokens do
        local flag = tokens[cursor]
        local name = flagName(flag)
        local value = tokens[cursor + 1]
        if flag == "-limit" then
            local count = value and tonumber(value)
            if count and count > 0 then
                opts.limit = math.floor(count)
                cursor = cursor + 2
            else
                -- No positive number after it: flag the mistake so the caller can nudge instead of silently whispering everyone.
                opts.limitError = true
                cursor = cursor + 1
            end
        elseif flag == "-cd" then
            opts.useCooldown = true
            local seconds = value and parseDuration(value)
            if seconds then
                opts.cooldownSeconds = seconds
                cursor = cursor + 2
            elseif value and value:match("^%d") then
                -- A digit-led token that isn't a duration is a typo ("3o", "0", "30x"), not message text.
                opts.cdError = value
                cursor = cursor + 2
            else
                cursor = cursor + 1
            end
        elseif BRACKET_FLAGS[name] then
            local content, mistake, nextCursor = readBracket(tokens, cursor, name)
            if not content then
                if not opts.bracketError then opts.bracketError = { flag = name, mistake = mistake } end
            elseif name == "-who" then
                opts.who = content
            else
                -- -skip and -only may repeat; every group adds to the same bucket.
                local bucket = opts[BRACKET_FLAGS[name]]
                for _, term in ipairs(splitTerms(content)) do bucket[#bucket + 1] = term end
            end
            cursor = nextCursor
        else
            break
        end
    end
    local words = {}
    for i = cursor, #tokens do words[#words + 1] = tokens[i] end
    opts.text = table.concat(words, " ")

    -- A known flag inside the message is a misplaced flag, not text to whisper; flags only parse before the message.
    for _, word in ipairs(words) do
        local lowered = word:lower()
        if FLAG_WORDS[lowered] or FLAG_WORDS[flagName(lowered)] then
            opts.flagError = word
            break
        end
    end

    -- A message of only semicolons splits to nothing; treat it as empty so the usage checks catch it.
    if #ns.SplitWhisper(opts.text) == 0 then opts.text = "" end
    return opts
end

-- One worked example per bracket flag and one line per way a group can go wrong, so the nudge names the actual slip.
local BRACKET_EXAMPLES = {
    ["-who"] = "-who (mage 50-60 stormwind)",
    ["-skip"] = "-skip (warlock z-maraudon)",
    ["-only"] = "-only (priest c-paladin)",
}
local BRACKET_MISTAKES = {
    open = "",
    empty = "They're empty.",
    close = "The closing one is missing.",
}

-- Report the first flag mistake so the caller aborts instead of whispering a typo. allowCooldown is false for commands that reject -cd outright, so they can say so instead of correcting its duration.
local function flagMistake(opts, allowCooldown)
    local bracket = opts.bracketError
    if bracket then
        -- Diagnosed first: a group that fell through leaves its words stranded in the message, and blaming those would hide the real mistake.
        local why = BRACKET_MISTAKES[bracket.mistake]
        fail(bracket.flag .. " needs brackets.", (why ~= "" and (why .. " ") or "") .. "e.g. " .. BRACKET_EXAMPLES[bracket.flag] .. ".")
    elseif opts.limitError then
        fail("-limit needs a number.", "e.g. -limit 10.")
    elseif allowCooldown and opts.cdError then
        fail("-cd needs a duration.", "\"" .. opts.cdError .. "\" isn't one. " .. DURATION_HINT)
    elseif opts.flagError then
        fail("Flags go before the message.", "\"" .. opts.flagError .. "\" landed inside it.")
    else
        return false
    end
    return true
end

-- A -who that failed to parse still counts as used, so commands without a /who can reject it by name.
local function usedWho(opts)
    return opts.who ~= nil or (opts.bracketError ~= nil and opts.bracketError.flag == "-who")
end

-- A keyed term matches one field; a bare term is a substring of the class, the zone or the name, so "war" catches Warriors, Warsong Gulch and Warence alike.
local function matchesTerm(whoInfo, term)
    local fields = { class = whoInfo.classStr, zone = whoInfo.area, name = whoInfo.fullName }
    if term.field then
        return (fields[term.field] or ""):lower():find(term.text, 1, true) ~= nil
    end
    for _, value in pairs(fields) do
        if value and value:lower():find(term.text, 1, true) then return true end
    end
    return false
end

local function isFiltered(whoInfo, terms)
    for _, term in ipairs(terms) do
        if matchesTerm(whoInfo, term) then return true end
    end
    return false
end

-- -only is the inverse of -skip: with terms set, a player must match at least one term to qualify. No terms = everyone.
local function isIncluded(whoInfo, includeTerms)
    if #includeTerms == 0 then return true end
    for _, term in ipairs(includeTerms) do
        if matchesTerm(whoInfo, term) then return true end
    end
    return false
end

ns.Trim = trim
ns.ParseFlags = parseFlags
ns.FlagMistake = flagMistake
ns.UsedWho = usedWho
ns.IsFiltered = isFiltered
ns.IsIncluded = isIncluded
