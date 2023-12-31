local utils = require 'utils'
local MultiMap = require 'interpolate/MultiMap'
local entry = require 'interpolate/entry'
local unpack = unpack or table.unpack ---@diagnostic disable-line: deprecated
local select = select
local tostring = tostring
local tonumber = tonumber


---Built-in interpolator function libraries.
---@class omi.interpolate.Libraries
local libraries = {}

---Contains library function tables.
---@type table<string, table<string, fun(interpolator: omi.interpolate.Interpolator, ...: unknown): unknown?>>
libraries.functions = {}


local nan = tostring(0 / 0)


---Wrapper that converts the first argument to a string.
---@param f function
---@return function
local function firstToString(f)
    return function(_, ...)
        return f(tostring(select(1, ...) or ''), select(2, ...))
    end
end

---Wrapper for functions that expect a single string argument.
---Concatenates arguments into one argument.
---@param f function
---@return function
local function concatenateArgs(f)
    return function(_, ...)
        return f(utils.concat({ ... }))
    end
end

---Wrapper for comparator functions.
---@param f function
---@return function
local function comparator(f)
    return function(_, this, other)
        this = tostring(this or '')
        other = tostring(other or '')

        local nThis = tonumber(this)
        local nOther = tonumber(other)

        if nThis and nOther then
            return f(nThis, nOther)
        end

        return f(this, other)
    end
end

---Wrapper for unary math functions.
---@param f function
---@return function
local function unary(f)
    return function(_, ...)
        local value = tonumber(utils.concat({ ... }))
        if value then
            return f(value)
        end
    end
end

---Wrapper for unary math functions with multiple returns.
---@param f function
---@return function
local function unaryList(f)
    return function(self, ...)
        local value = tonumber(utils.concat({ ... }))
        if not value then
            return
        end

        return libraries.functions.map.list(self, f(value))
    end
end

---Wrapper for binary math functions.
---@param f function
---@return function
local function binary(f)
    return function(_, x, ...)
        x = tonumber(tostring(x))
        if not x then
            return
        end

        local y = tonumber(utils.concat({ ... }))
        if y then
            return f(x, y)
        end
    end
end

---Wrapper for pcall in interpolation functions.
---@param f function
---@param ... unknown
---@return ...
local function try(f, ...)
    local results = { pcall(f, ...) }
    if not results[1] then
        return
    end

    return unpack(results, 2)
end

---Wrapper for pcall in interpolation functions.
---Wraps return values as a list.
---@param f function
---@param interpolator omi.interpolate.Interpolator
---@param ... unknown
---@return omi.interpolate.MultiMap?
local function tryList(f, interpolator, ...)
    local results = { pcall(f, ...) }

    if not results[1] then
        return
    end

    return libraries.functions.map.list(interpolator, unpack(results, 2))
end


---Contains math functions.
libraries.functions.math = {
    pi = function() return math.pi end,
    isnan = function(_, n) return tostring(n) == nan end,
    abs = unary(math.abs),
    acos = unary(math.acos),
    add = binary(function(x, y) return x + y end),
    asin = unary(math.asin),
    atan = unary(math.atan),
    atan2 = binary(math.atan2),
    ceil = unary(math.ceil),
    cos = unary(math.cos),
    cosh = unary(math.cosh),
    deg = unary(math.deg),
    div = binary(function(x, y) return x / y end),
    exp = unary(math.exp),
    floor = unary(math.floor),
    fmod = binary(math.fmod),
    frexp = unaryList(math.frexp),
    int = unary(math.modf),
    ldexp = binary(math.ldexp),
    log = unary(function(x)
        return try(math.log, x)
    end),
    log10 = unary(function(x)
        return try(math.log10, x)
    end),
    max = function(_, ...)
        local max
        local strComp = not utils.all(tonumber, { ... })

        for i = 1, select('#', ...) do
            local arg = select(i, ...)
            arg = strComp and tostring(arg) or tonumber(arg)

            if not max or (arg and arg > max) then
                max = arg
            end
        end

        return max
    end,
    min = function(_, ...)
        local min
        local strComp = not utils.all(tonumber, { ... })

        for i = 1, select('#', ...) do
            local arg = select(i, ...)
            arg = strComp and tostring(arg) or tonumber(arg)

            if not min or (arg and arg < min) then
                min = arg
            end
        end

        return min
    end,
    mod = binary(function(x, y) return x % y end),
    modf = unaryList(math.modf),
    mul = binary(function(x, y) return x * y end),
    num = concatenateArgs(tonumber),
    pow = binary(math.pow),
    rad = unary(math.rad),
    sin = unary(math.sin),
    sinh = unary(math.sinh),
    subtract = binary(function(x, y) return x - y end),
    sqrt = unary(math.sqrt),
    tan = unary(math.tan),
    tanh = unary(math.tanh),
}

---Contains string functions.
libraries.functions.string = {
    str = concatenateArgs(tostring),
    lower = concatenateArgs(string.lower),
    upper = concatenateArgs(string.upper),
    reverse = concatenateArgs(string.reverse),
    trim = concatenateArgs(utils.trim),
    trimleft = concatenateArgs(utils.trimleft),
    trimright = concatenateArgs(utils.trimright),
    first = concatenateArgs(function(s) return s:sub(1, 1) end),
    last = concatenateArgs(function(s) return s:sub(-1) end),
    contains = firstToString(function(s, other) return utils.contains(s, tostring(other or '')) end),
    startswith = firstToString(function(s, other) return utils.startsWith(s, tostring(other or '')) end),
    endswith = firstToString(function(s, other) return utils.endsWith(s, tostring(other or '')) end),
    concat = function(_, ...) return utils.concat({ ... }) end,
    concats = firstToString(function(sep, ...) return utils.concat({ ... }, sep) end),
    len = function(_, ...) return #utils.concat({ ... }) end,
    capitalize = firstToString(function(s) return s:sub(1, 1):upper() .. s:sub(2) end),
    punctuate = firstToString(function(s, punctuation, chars)
        punctuation = tostring(punctuation or '.')
        chars = tostring(chars or '')

        local patt
        if chars ~= '' then
            patt = table.concat { '[', utils.escape(chars), ']$' }
        else
            patt = '%p$'
        end

        if not s:match(patt) then
            s = s .. punctuation
        end

        return s
    end),
    gsub = function(interpolator, s, pattern, repl, n)
        s = tostring(s or '')
        pattern = tostring(pattern or '')
        repl = tostring(repl or '')
        n = tonumber(n)
        return tryList(string.gsub, interpolator, s, pattern, repl, n)
    end,
    sub = firstToString(function(s, i, j)
        i = tonumber(i)
        if not i then
            return
        end

        j = tonumber(j)
        return j and s:sub(i, j) or s:sub(i)
    end),
    index = firstToString(function(s, i, d)
        i = tonumber(i)
        if i and i < 0 then
            i = #s + i + 1
        end

        if not i or i > #s or i < 1 then
            return d
        end

        return s:sub(i, i)
    end),
    match = function(interpolator, s, pattern, init)
        s = tostring(s or '')
        pattern = tostring(pattern or '')
        init = tonumber(init) or 1
        return tryList(string.match, interpolator, s, pattern, init)
    end,
    char = function(interpolator, ...)
        local args = {}

        local o = select(1, ...)
        if select('#', ...) == 1 and utils.isinstance(o, MultiMap) then
            ---@cast o omi.interpolate.MultiMap
            for _, value in o:pairs() do
                local num = tonumber(tostring(interpolator:convert(value)))
                if not num then
                    return
                end

                args[#args + 1] = num
            end

            return try(string.char, unpack(args))
        end

        for i = 1, select('#', ...) do
            local num = tonumber(tostring(interpolator:convert(select(i, ...))))
            if not num then
                return
            end

            args[#args + 1] = num
        end

        return try(string.char, unpack(args))
    end,
    byte = function(interpolator, s, i, j)
        i = tonumber(i or 1)
        if not i then
            return
        end

        j = tonumber(j or i)
        if not j then
            return
        end

        s = tostring(s or '')
        return tryList(string.byte, interpolator, s, i, j)
    end,
    rep = firstToString(function(s, n, sep)
        n = tonumber(n)
        if not n or n < 1 then
            return
        end

        return try(string.rep, s, n, tostring(sep or ''))
    end),
}

---Contains boolean functions.
libraries.functions.boolean = {
    ['not'] = function(interpolator, value)
        return not interpolator:toBoolean(value)
    end,
    eq = comparator(function(s, other) return s == other end),
    neq = comparator(function(s, other) return s ~= other end),
    gt = comparator(function(a, b) return a > b end),
    lt = comparator(function(a, b) return a < b end),
    gte = comparator(function(a, b) return a >= b end),
    lte = comparator(function(a, b) return a <= b end),
    any = function(interpolator, ...)
        for i = 1, select('#', ...) do
            local value = select(i, ...)
            if interpolator:toBoolean(value) then
                return value
            end
        end
    end,
    all = function(interpolator, ...)
        local n = select('#', ...)
        if n == 0 then
            return
        end

        for i = 1, n do
            if not interpolator:toBoolean(select(i, ...)) then
                return
            end
        end

        return select(n, ...)
    end,
    ['if'] = function(interpolator, condition, ...)
        if interpolator:toBoolean(condition) then
            return utils.concat({ ... })
        end
    end,
    unless = function(interpolator, condition, ...)
        if not interpolator:toBoolean(condition) then
            return utils.concat({ ... })
        end
    end,
    ifelse = function(interpolator, condition, yes, ...)
        if interpolator:toBoolean(condition) then
            return yes
        end

        return utils.concat({ ... })
    end,
}

---Contains functions related to translation.
libraries.functions.translation = {
    gettext = firstToString(function(...)
        if not getText then
            return ''
        end

        return getText(unpack(utils.pack(utils.map(tostring, { ... })), 1, 5))
    end),
    gettextornull = firstToString(function(...)
        if not getTextOrNull then
            return ''
        end

        return getTextOrNull(unpack(utils.pack(utils.map(tostring, { ... })), 1, 5))
    end),
}

---Contains functions related to at-maps.
libraries.functions.map = {
    ---Creates a list. If a single argument is provided and it is an at-map, its values will be used.
    ---Otherwise, the list is made up of all provided arguments.
    list = function(interpolator, ...)
        local entries = {}
        local o = select(1, ...)
        if not o then
            return
        end

        if select('#', ...) ~= 1 or not utils.isinstance(o, MultiMap) then
            for i = 1, select('#', ...) do
                o = interpolator:convert(select(i, ...))
                entries[#entries + 1] = entry(interpolator:convert(#entries + 1), o)
            end

            return MultiMap:new(entries)
        end

        ---@cast o omi.interpolate.MultiMap
        for _, value in o:pairs() do
            value = interpolator:convert(value)
            entries[#entries + 1] = entry(interpolator:convert(#entries + 1), value)
        end

        return MultiMap:new(entries)
    end,
    map = function(interpolator, func, o, ...)
        if not utils.isinstance(o, MultiMap) then
            return
        end

        local entries = {}

        ---@cast o omi.interpolate.MultiMap
        for key, value in o:pairs() do
            value = interpolator:convert(interpolator:execute(func, { value, ... }))
            entries[#entries + 1] = entry(key, value)
        end

        return MultiMap:new(entries)
    end,
    len = function(interpolator, ...)
        local o = select(1, ...)
        if select('#', ...) ~= 1 or not utils.isinstance(o, MultiMap) then
            return libraries.functions.string.len(interpolator, ...)
        end

        ---@cast o omi.interpolate.MultiMap
        return o:size()
    end,
    concat = function(interpolator, ...)
        local o = select(1, ...)
        if select('#', ...) ~= 1 or not utils.isinstance(o, MultiMap) then
            return libraries.functions.string.concat(interpolator, ...)
        end

        ---@cast o omi.interpolate.MultiMap
        return o:concat()
    end,
    concats = function(interpolator, sep, ...)
        local o = select(1, ...)
        if select('#', ...) ~= 1 or not utils.isinstance(o, MultiMap) then
            return libraries.functions.string.concats(interpolator, sep, ...)
        end

        ---@cast o omi.interpolate.MultiMap
        return o:concat(sep)
    end,
    nthvalue = function(_, o, n)
        if not o or not utils.isinstance(o, MultiMap) then
            return
        end

        n = tonumber(n)
        if not n then
            return
        end

        ---@cast o omi.interpolate.MultiMap
        local e = o:entry(n)
        if e then
            return e.value
        end
    end,
    first = function(interpolator, ...)
        local o = select(1, ...)
        if select('#', ...) ~= 1 or not utils.isinstance(o, MultiMap) then
            return libraries.functions.string.first(interpolator, ...)
        end

        ---@cast o omi.interpolate.MultiMap
        return o:first()
    end,
    last = function(interpolator, ...)
        local o = select(1, ...)
        if select('#', ...) ~= 1 or not utils.isinstance(o, MultiMap) then
            return libraries.functions.string.last(interpolator, ...)
        end

        ---@cast o omi.interpolate.MultiMap
        return o:last()
    end,
    has = function(_, o, k)
        if not o or not utils.isinstance(o, MultiMap) then
            return
        end

        return o:has(k)
    end,
    get = function(_, o, k, d)
        if not o or not utils.isinstance(o, MultiMap) then
            return
        end

        return o:get(k, d)
    end,
    index = function(interpolator, o, i, d)
        if not utils.isinstance(o, MultiMap) then
            return libraries.functions.string.index(interpolator, o, i, d)
        end

        ---@cast o omi.interpolate.MultiMap
        return o:index(i, d)
    end,
    unique = function(_, o)
        if utils.isinstance(o, MultiMap) then
            ---@cast o omi.interpolate.MultiMap
            return o:unique()
        end
    end,
}

---Contains functions that can mutate interpolator state.
libraries.functions.mutators = {
    randomseed = function(interpolator, seed)
        return interpolator:randomseed(seed)
    end,
    random = function(interpolator, m, n)
        if m and not tonumber(m) then
            return
        end

        if n and not tonumber(n) then
            return
        end

        return interpolator:random(m, n)
    end,
    ---Returns a random element from the given options.
    ---If the sole argument provided is an at-map, a value is chosen from its values.
    choose = function(interpolator, ...)
        local o = select(1, ...)
        if select('#', ...) ~= 1 or not utils.isinstance(o, MultiMap) then
            return interpolator:randomChoice({ ... })
        end

        ---@cast o omi.interpolate.MultiMap
        local values = {}
        for _, value in o:pairs() do
            values[#values + 1] = value
        end

        return interpolator:randomChoice(values)
    end,
    ---Sets the value of an interpolation token.
    set = function(interpolator, token, ...)
        local value
        if select('#', ...) > 1 then
            value = utils.concat({ ... })
        else
            value = select(1, ...)
        end

        return interpolator:setTokenValidated(tostring(token), value)
    end,
}


---List of interpolator libraries in the order they should be loaded.
libraries.list = {
    'math',
    'boolean',
    'string',
    'translation',
    'map',
    'mutators',
}


---Returns a table of interpolator functions.
---@param include table<string, true>? A set of function or modules to include.
---@param exclude table<string, true>? A set of function or modules to exclude.
---@return table
function libraries:load(include, exclude)
    exclude = exclude or {}

    local result = {}

    for i = 1, #self.list do
        local lib = self.list[i]
        if (not include or include[lib]) and not exclude[lib] then
            local funcs = libraries.functions[lib]
            for k, func in pairs(funcs) do
                local name = table.concat({ lib, '.', k })
                if (not include or include[name]) and not exclude[name] then
                    result[k] = func
                end
            end
        end
    end

    return result
end


return libraries
