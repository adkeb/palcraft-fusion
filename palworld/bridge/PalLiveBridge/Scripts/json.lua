-- Pure Lua JSON codec for the bridge. No dependencies, load, eval, or I/O.
-- json.decode(text [, {max_bytes=1048576, max_depth=64}]) throws on invalid input.
-- json.encode(value [, {max_bytes=1048576, max_depth=64}]) throws on invalid data.
-- null has a sentinel; empty plain tables encode as {}, json.array({}) as [].
-- GUIDs / Steam IDs must remain strings, not JSON numbers.
local json = {}
local array_mt = {}
json.null = setmetatable({}, {__tostring = function() return "json.null" end})

function json.array(t)
    assert(t == nil or type(t) == "table", "array expects a table")
    return setmetatable(t or {}, array_mt)
end

local function limits(options)
    options = options or {}
    local bytes, depth = options.max_bytes or 1048576, options.max_depth or 64
    assert(type(bytes) == "number" and bytes > 0 and bytes % 1 == 0, "invalid max_bytes")
    assert(type(depth) == "number" and depth > 0 and depth % 1 == 0, "invalid max_depth")
    return bytes, depth
end

local function check_utf8(s)
    -- UE4SS embeds Lua 5.4; its standard UTF-8 library validates encoded strings.
    if utf8 and utf8.len then
        local length = utf8.len(s)
        if not length then error("JSON: invalid UTF-8", 0) end
    end
end

local escapes = {['"']='\\"', ['\\']='\\\\', ['\b']='\\b', ['\f']='\\f',
                 ['\n']='\\n', ['\r']='\\r', ['\t']='\\t'}
local function quote(s)
    check_utf8(s)
    return '"' .. s:gsub('[%z\1-\31\\"]', function(c)
        return escapes[c] or string.format("\\u%04x", c:byte())
    end) .. '"'
end

function json.encode(value, options)
    local max_bytes, max_depth = limits(options)
    local active, output, total = {}, {}, 0
    local function emit(s)
        total = total + #s
        if total > max_bytes then error("JSON: output exceeds max_bytes", 0) end
        output[#output + 1] = s
    end
    local encode
    encode = function(v, depth)
        if depth > max_depth then error("JSON: nesting exceeds max_depth", 0) end
        local kind = type(v)
        if v == json.null or kind == "nil" then emit("null")
        elseif kind == "boolean" then emit(v and "true" or "false")
        elseif kind == "string" then emit(quote(v))
        elseif kind == "number" then
            if v ~= v or v == math.huge or v == -math.huge then
                error("JSON: non-finite number", 0)
            end
            local s = (math.type and math.type(v) == "integer") and tostring(v) or string.format("%.17g", v)
            if s:find(",", 1, true) then error("JSON: non-C numeric locale", 0) end
            emit(s)
        elseif kind == "table" then
            if active[v] then error("JSON: cyclic table", 0) end
            local mt = getmetatable(v)
            if mt ~= nil and mt ~= array_mt then error("JSON: unsupported table metatable", 0) end
            active[v] = true
            local count, highest, has_string = 0, 0, false
            for k in next, v do
                count = count + 1
                if type(k) == "number" and k >= 1 and k % 1 == 0 then
                    highest = math.max(highest, k)
                elseif type(k) == "string" then has_string = true
                else error("JSON: object keys must be strings or dense array indexes", 0) end
            end
            local is_array = mt == array_mt or (count > 0 and not has_string)
            if is_array then
                if has_string or highest ~= count then error("JSON: sparse or mixed array", 0) end
                emit("[")
                for i = 1, highest do
                    if i > 1 then emit(",") end
                    encode(rawget(v, i), depth + 1)
                end
                emit("]")
            else
                if highest > 0 then error("JSON: mixed object and array", 0) end
                local keys = {}
                for k in next, v do keys[#keys + 1] = k end
                table.sort(keys)
                emit("{")
                for i, k in ipairs(keys) do
                    if i > 1 then emit(",") end
                    emit(quote(k)); emit(":"); encode(rawget(v, k), depth + 1)
                end
                emit("}")
            end
            active[v] = nil
        else error("JSON: unsupported type " .. kind, 0) end
    end
    encode(value, 0)
    return table.concat(output)
end

local unescapes = {['"']='"', ['\\']='\\', ['/']='/', b='\b', f='\f', n='\n', r='\r', t='\t'}
local function codepoint(n)
    if n < 0x80 then return string.char(n)
    elseif n < 0x800 then return string.char(0xc0 + math.floor(n / 64), 0x80 + n % 64)
    elseif n < 0x10000 then
        return string.char(0xe0 + math.floor(n / 4096), 0x80 + math.floor(n / 64) % 64, 0x80 + n % 64)
    end
    return string.char(0xf0 + math.floor(n / 262144), 0x80 + math.floor(n / 4096) % 64,
                       0x80 + math.floor(n / 64) % 64, 0x80 + n % 64)
end

function json.decode(text, options)
    assert(type(text) == "string", "JSON: decode expects a string")
    local max_bytes, max_depth = limits(options)
    if #text > max_bytes then error("JSON: input exceeds max_bytes", 0) end
    check_utf8(text)
    local pos, length = 1, #text
    local function fail(message) error("JSON at byte " .. pos .. ": " .. message, 0) end
    local function ws()
        while pos <= length do
            local c = text:byte(pos)
            if c == 32 or c == 9 or c == 10 or c == 13 then pos = pos + 1 else break end
        end
    end
    local function hex4()
        local s = text:sub(pos, pos + 3)
        if #s ~= 4 or s:find("[^%x]") then fail("invalid Unicode escape") end
        pos = pos + 4
        return tonumber(s, 16)
    end
    local function string_value()
        pos = pos + 1
        local parts, start = {}, pos
        while pos <= length do
            local c = text:byte(pos)
            if c == 34 then
                parts[#parts + 1] = text:sub(start, pos - 1)
                pos = pos + 1
                return table.concat(parts)
            elseif c == 92 then
                parts[#parts + 1] = text:sub(start, pos - 1)
                pos = pos + 1
                local escape = text:sub(pos, pos)
                pos = pos + 1
                if escape == "u" then
                    local n = hex4()
                    if n >= 0xd800 and n <= 0xdbff then
                        if text:sub(pos, pos + 1) ~= "\\u" then fail("missing low surrogate") end
                        pos = pos + 2
                        local low = hex4()
                        if low < 0xdc00 or low > 0xdfff then fail("invalid low surrogate") end
                        n = 0x10000 + (n - 0xd800) * 0x400 + low - 0xdc00
                    elseif n >= 0xdc00 and n <= 0xdfff then fail("unpaired low surrogate") end
                    parts[#parts + 1] = codepoint(n)
                elseif unescapes[escape] then parts[#parts + 1] = unescapes[escape]
                else fail("invalid escape") end
                start = pos
            elseif c < 32 then fail("unescaped control character")
            else pos = pos + 1 end
        end
        fail("unterminated string")
    end
    local function digit() local c = text:byte(pos); return c and c >= 48 and c <= 57 end
    local function number_value()
        local start = pos
        if text:sub(pos, pos) == "-" then pos = pos + 1 end
        if text:sub(pos, pos) == "0" then pos = pos + 1
        elseif digit() then repeat pos = pos + 1 until not digit()
        else fail("invalid number") end
        if text:sub(pos, pos) == "." then
            pos = pos + 1
            if not digit() then fail("missing fractional digits") end
            repeat pos = pos + 1 until not digit()
        end
        local c = text:sub(pos, pos)
        if c == "e" or c == "E" then
            pos = pos + 1
            c = text:sub(pos, pos)
            if c == "+" or c == "-" then pos = pos + 1 end
            if not digit() then fail("missing exponent digits") end
            repeat pos = pos + 1 until not digit()
        end
        local n = tonumber(text:sub(start, pos - 1))
        if not n or n ~= n or n == math.huge or n == -math.huge then fail("number out of range") end
        return n
    end
    local value
    value = function(depth)
        if depth > max_depth then fail("nesting exceeds max_depth") end
        ws()
        local c = text:sub(pos, pos)
        if c == '"' then return string_value()
        elseif c == "{" then
            pos = pos + 1; ws()
            local result = {}
            if text:sub(pos, pos) == "}" then pos = pos + 1; return result end
            while true do
                if text:sub(pos, pos) ~= '"' then fail("object key must be a string") end
                local key = string_value(); ws()
                if text:sub(pos, pos) ~= ":" then fail("expected colon") end
                if rawget(result, key) ~= nil then fail("duplicate object key") end
                pos = pos + 1; result[key] = value(depth + 1); ws()
                c = text:sub(pos, pos); pos = pos + 1
                if c == "}" then return result end
                if c ~= "," then fail("expected comma or closing brace") end
                ws()
            end
        elseif c == "[" then
            pos = pos + 1; ws()
            local result = json.array()
            if text:sub(pos, pos) == "]" then pos = pos + 1; return result end
            while true do
                result[#result + 1] = value(depth + 1); ws()
                c = text:sub(pos, pos); pos = pos + 1
                if c == "]" then return result end
                if c ~= "," then fail("expected comma or closing bracket") end
            end
        elseif c == "-" or digit() then return number_value()
        elseif text:sub(pos, pos + 3) == "true" then pos = pos + 4; return true
        elseif text:sub(pos, pos + 4) == "false" then pos = pos + 5; return false
        elseif text:sub(pos, pos + 3) == "null" then pos = pos + 4; return json.null
        else fail("unexpected token") end
    end
    local result = value(0); ws()
    if pos <= length then fail("trailing content") end
    return result
end

return json
