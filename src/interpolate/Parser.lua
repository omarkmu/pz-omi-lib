local BaseParser = require 'fmt/Parser'
local utils = require 'utils'

local concat = table.concat


---Parser for the interpolated string format.
---@class omi.interpolate.Parser : omi.fmt.Parser
---@field NodeType table<omi.interpolate.NodeType, string>
---@field protected _allowTokens boolean
---@field protected _allowAtExpr boolean
---@field protected _allowFunctions boolean
---@field protected _allowCharEntities boolean
local InterpolationParser = BaseParser:derive()


---@class omi.interpolate.ParserOptions : omi.fmt.ParserOptions
---@field allowTokens boolean?
---@field allowFunctions boolean?
---@field allowAtExpressions boolean?
---@field allowCharacterEntities boolean?

---@alias omi.interpolate.Result
---| { success: true, value: omi.interpolate.Node[], warnings: omi.fmt.ParserError[]? }
---| { success: false, errors: omi.fmt.ParserError[], warnings: omi.fmt.ParserError[]? }

---@alias omi.interpolate.Node
---| omi.interpolate.ValueNode
---| omi.interpolate.CallNode
---| omi.interpolate.AtExpressionNode

---@alias omi.interpolate.Argument omi.interpolate.ValueNode[]

---@class omi.interpolate.ValueNode
---@field type omi.interpolate.NodeType
---@field value string

---@class omi.interpolate.CallNode : omi.interpolate.ValueNode
---@field args omi.interpolate.Node[][]

---@class omi.interpolate.AtExpressionEntry
---@field key omi.interpolate.ValueNode[]
---@field value omi.interpolate.ValueNode[]

---@class omi.interpolate.AtExpressionNode
---@field type omi.interpolate.NodeType
---@field entries omi.interpolate.AtExpressionEntry[]


---@alias omi.interpolate.NodeType
---| 'at_expression'
---| 'at_key'
---| 'at_value'
---| 'text'
---| 'token'
---| 'string'
---| 'call'
---| 'escape'
---| 'argument'

InterpolationParser.NodeType = {
    at_expression = 'at_expression',
    at_key = 'at_key',
    at_value = 'at_value',
    text = 'text',
    token = 'token',
    string = 'string',
    call = 'call',
    escape = 'escape',
    argument = 'argument',
}

local NodeType = InterpolationParser.NodeType
local ERR = {
    BAD_CHAR = 'unexpected character: `%s`',
    WARN_UNTERM_FUNC = 'potentially unterminated function `%s`',
    UNTERM_FUNC = 'unterminated function `%s`',
    UNTERM_AT = 'unterminated at-expression',
}

-- text patterns for node types
local TEXT_PATTERNS = {
    -- $ = token/escape/call start, space = delimiter, ( = string start, ) = call end, & = entity start
    [NodeType.argument] = ' $%(%)&',
    -- $ = token/escape/call start, @ = at-expression start, ; = delim, : = delimiter, ( = string start, ) = expression end, & = entity start
    [NodeType.at_key] = ':;$@%(%)&',
    [NodeType.at_value] = ':;$@%(%)&',
    -- $ = escape start, ) = string end
    [NodeType.string] = '$%)',
}

local SPECIAL = {
    ['$'] = true,
    ['@'] = true,
    [':'] = true,
    [';'] = true,
    ['('] = true,
    [')'] = true,
    ['&'] = true,
}


---Returns a table with consecutive text nodes merged.
---@param tab omi.fmt.ParseTreeNode[]
---@return omi.fmt.ParseTreeNode[]
---@protected
function InterpolationParser:mergeTextNodes(tab)
    local result = {}

    local last
    for i = 1, #tab do
        local node = tab[i]
        if node.type == NodeType.text then
            if last and last.parts and last.type == NodeType.text then
                last.parts[#last.parts + 1] = node.value
            else
                last = {
                    type = NodeType.text,
                    parts = { node.value },
                }

                result[#result + 1] = last
            end
        else
            result[#result + 1] = node
            last = node
        end
    end

    for i = 1, #result do
        local node = result[i]
        if node.parts and node.type == NodeType.text then
            node.value = concat(node.parts)
            node.parts = nil
        end
    end

    return result
end

---Performs postprocessing on a tree node.
---@param node omi.fmt.ParseTreeNode
---@return omi.fmt.ParseTreeNode?
---@protected
function InterpolationParser:postprocessNode(node)
    local nodeType = node.type

    if nodeType == NodeType.text or nodeType == NodeType.escape then
        return {
            type = NodeType.text,
            value = node.value,
        }
    elseif nodeType == NodeType.token then
        return {
            type = nodeType,
            value = node.value,
        }
    elseif nodeType == NodeType.string then
        -- convert string to basic text node
        local parts = {}
        if node.children then
            for i = 1, #node.children do
                local built = self:postprocessNode(node.children[i])
                if built and built.value then
                    parts[#parts + 1] = built.value
                end
            end
        end

        return {
            type = NodeType.text,
            value = concat(parts),
        }
    elseif nodeType == NodeType.argument or nodeType == NodeType.at_key or nodeType == NodeType.at_value then
        -- convert node to list of child nodes
        local parts = {}
        if node.children then
            for i = 1, #node.children do
                local built = self:postprocessNode(node.children[i])
                if built then
                    parts[#parts + 1] = built
                end
            end
        end

        return self:mergeTextNodes(parts)
    elseif nodeType == NodeType.call then
        local args = {}

        if node.children then
            for i = 1, #node.children do
                local child = node.children[i]
                local type = child.type
                if type == NodeType.argument then
                    args[#args + 1] = self:postprocessNode(child)
                end
            end
        end

        return {
            type = node.type,
            value = node.value,
            args = args,
        }
    elseif nodeType == NodeType.at_expression then
        local children = node.children or {}
        local entries = {}

        local i = 1
        while i <= #children do
            local key = children[i]
            local builtKey = key and key.type == NodeType.at_key and self:postprocessNode(key)

            if builtKey then
                local value = children[i + 1]
                local builtValue = value and value.type == NodeType.at_value and self:postprocessNode(value)

                if builtValue then
                    entries[#entries + 1] = {
                        key = builtKey,
                        value = builtValue,
                    }

                    i = i + 1
                else
                    builtValue = builtKey
                    entries[#entries + 1] = {
                        value = builtValue,
                    }
                end
            end

            i = i + 1
        end

        return {
            type = NodeType.at_expression,
            entries = entries,
        }
    end
end

---Gets the value of a named or numeric entity.
---@param entity string
---@return string
---@protected
function InterpolationParser:getEntityValue(entity)
    return utils.getEntityValue(entity) or entity
end

---Gets the pattern for text nodes given the current node type.
---@return string
---@protected
function InterpolationParser:getTextPattern()
    local type = self._node and self._node.type

    -- $ = token/escape/call start, @ = at-expression start, & = entity start
    local patt = TEXT_PATTERNS[type] or '$@&'
    return string.format('^([^%s])[%s]?', patt, patt)
end

---Reads space characters and returns a literal string of spaces.
---@return string?
---@protected
function InterpolationParser:readSpaces()
    local spaces = self:match('^( +)')
    if not spaces then
        return
    end

    self:forward(#spaces)
    return spaces
end

---Reads a prefix followed by an escaped character.
---@return omi.fmt.ParseTreeNode?
---@protected
function InterpolationParser:readEscape()
    local value = self:match('^$([$@();:&])')
    if not value then
        return
    end

    local node = self:createNode(NodeType.escape, { value = value })

    self:setNodeEnd(node, self:pos() + 1)
    self:forward(2)

    return self:addNode(node)
end

---Reads as much text as possible, up to the next special character.
---@return omi.fmt.ParseTreeNode?
---@protected
function InterpolationParser:readText()
    local value = self:match(self:getTextPattern())
    if not value then
        return
    end

    local node = self:createNode(NodeType.text, { value = value })

    self:setNodeEnd(node, self:pos() + #value - 1)
    self:forward(#value)

    return self:addNode(node)
end

---Reads a special character as-is.
---@return omi.fmt.ParseTreeNode?
---@protected
function InterpolationParser:readSpecialText()
    local value = self:peek()
    if not SPECIAL[value] then
        return
    end

    local node = self:createNode(NodeType.text, { value = value })
    self:forward()

    return self:addNode(node)
end

---Reads a string of literal text delimited by parentheses. Special characters can be escaped with $.
---@return omi.fmt.ParseTreeNode?
---@protected
function InterpolationParser:readString()
    if self:peek() ~= '(' then
        return
    end

    local stop
    local node = self:createNode(NodeType.string)
    local parent = self:setCurrentNode(node)
    self:forward()

    while self:pos() <= self:len() do
        if self:peek() == ')' then
            break
        end

        if not (self:readEscape() or self:readText() or self:readSpecialText()) then
            self:errorHere(ERR.BAD_CHAR:format(self:peek()), node)
            stop = self:pos() - 1

            break
        end
    end

    self:setNodeEnd(node, stop)
    self:setCurrentNode(parent)

    if self:peek() ~= ')' then
        -- unterminated string; read as open parenthesis and rewind
        self:pos(node.range[1])
        node = self:createNode(NodeType.text, { value = '(' })
    end

    self:forward()
    return self:addNode(node)
end

---Reads a variable token (e.g., `$var`).
---@return omi.fmt.ParseTreeNode?
---@protected
function InterpolationParser:readVariable()
    if not self._allowTokens then
        return
    end

    local name, pos = self:match('^$([%w_]+)()')

    if not name then
        return
    end

    local node = self:createNode(NodeType.token, { value = name })
    self:setNodeEnd(node, pos - 1)
    self:pos(pos)

    return self:addNode(node)
end

---Reads a character entity (e.g., `&#171;`)
---@return omi.fmt.ParseTreeNode?
---@protected
function InterpolationParser:readCharacterEntity()
    if not self._allowCharEntities then
        return
    end

    local entity, pos = self:match('^(&#x?%d+;)()')

    if not entity then
        entity, pos = self:match('^(&%a+;)()')
        if not entity then
            return
        end
    end

    local value = self:getEntityValue(entity)
    if not value then
        return
    end

    local node = self:createNode(NodeType.text, { value = value })
    self:setNodeEnd(node, pos - 1)
    self:pos(pos)

    return self:addNode(node)
end

---Reads a function and its arguments (e.g., `$upper(hello)`).
---@return omi.fmt.ParseTreeNode?
---@protected
function InterpolationParser:readFunction()
    if not self._allowFunctions then
        return
    end

    local name, start = self:match('^$([%w_]+)%(()')
    if not name then
        return
    end

    local node = self:createNode(NodeType.call, { value = name })
    local parent = self:setCurrentNode(node)
    self:pos(start)

    local argNode = self:createNode(NodeType.argument)
    self:setCurrentNode(argNode)

    local stop
    while self:pos() <= self:len() do
        local delimited = self:readSpaces()
        local done = self:peek() == ')'
        if delimited or done then
            self:setCurrentNode(node)

            if argNode.children and #argNode.children > 0 then
                self:addNode(argNode)
            end

            if done or self:pos() > self:len() then
                break
            end

            argNode = self:createNode(NodeType.argument)
            self:setCurrentNode(argNode)
        end

        if not (self:readString() or self:readExpression()) then
            self:errorHere(ERR.BAD_CHAR:format(self:peek()), argNode)
            stop = self:pos() - 1

            break
        end
    end

    self:setCurrentNode(parent)

    if self:peek() ~= ')' then
        -- unterminated function; read as var and rewind
        self:pos(node.range[1])

        local variableNode = self:readVariable()
        if variableNode then
            self:warning(ERR.WARN_UNTERM_FUNC:format(name), node)
            return variableNode
        end

        self:error(ERR.UNTERM_FUNC:format(name), node)
    end

    self:setNodeEnd(node, stop)
    self:forward()
    return self:addNode(node)
end

---Reads an at-expression (e.g., `@(1)`, `@(A:B)`, `@(1;A:B)`).
---@return omi.fmt.ParseTreeNode?
---@protected
function InterpolationParser:readAtExpression()
    if not self._allowAtExpr then
        return
    end

    local start = self:match('^@%(()')
    if not start then
        return
    end

    local node = self:createNode(NodeType.at_expression)
    local parent = self:setCurrentNode(node)
    self:pos(start)

    local stop, keyNode, valueNode

    self:readSpaces()

    while self:pos() <= self:len() do
        while self:peek() == ';' do
            keyNode = nil
            valueNode = nil
            self:forward()
        end

        if self:pos() > self:len() then
            break
        end

        if not keyNode then
            self:readSpaces()
        end

        local c = self:peek()
        if c == ')' then
            break
        elseif c == ':' then
            local keyPos = self:pos()

            -- consume :
            repeat
                self:forward()
            until self:peek() ~= ':'

            if self:pos() > self:len() then
                break
            end

            self:setCurrentNode(node)

            -- existing value node | no key node → add empty key node
            if valueNode or not keyNode then
                keyNode = self:addNode(self:createNode(NodeType.at_key))
                self:setNodeRange(keyNode, keyPos, keyPos)
            end

            self:readSpaces()

            valueNode = self:addNode(self:createNode(NodeType.at_value))
            self:setCurrentNode(valueNode)
        elseif not keyNode then
            self:setCurrentNode(node)
            keyNode = self:addNode(self:createNode(NodeType.at_key))
            self:setCurrentNode(keyNode)
        end

        c = self:peek()
        if c == ';' or c == ':' then
            -- ignore; avoid reading invalid value
        elseif c == ')' then
            if valueNode then
                local pos = self:pos()
                self:setNodeRange(valueNode, pos, pos)
            end

            break
        elseif not (self:readString() or self:readExpression()) then
            self:errorHere(ERR.BAD_CHAR:format(self:peek()), valueNode or keyNode or node)

            stop = self:pos() - 1
            self:setNodeEnd(self._node, stop)

            break
        elseif keyNode or valueNode then
            self:setNodeEnd(self._node, self:pos() - 1)
        end
    end

    self:setNodeEnd(node, stop)
    self:setCurrentNode(parent)

    if self:peek() ~= ')' then
        -- unterminated expression; read @ and rewind
        self:warning(ERR.UNTERM_AT, node)
        self:pos(node.range[1])
        node = self:createNode(NodeType.text, { value = '@' })
    end

    self:forward()
    return self:addNode(node)
end

---Reads a single acceptable expression.
---@return omi.fmt.ParseTreeNode?
---@protected
function InterpolationParser:readExpression()
    return self:readEscape()
        or self:readFunction()
        or self:readVariable()
        or self:readAtExpression()
        or self:readCharacterEntity()
        or self:readText()
        or self:readSpecialText()
end

---Performs postprocessing on a result tree.
---@return omi.interpolate.Result
---@protected
function InterpolationParser:postprocess()
    local tree = self._tree
    local result = {}
    if #self._errors > 0 then
        return {
            success = false,
            warnings = #self._warnings > 0 and self._warnings or nil,
            errors = self._errors,
        }
    end

    if not tree.children then
        return { success = true, value = result }
    end

    for i = 1, #tree.children do
        local built = self:postprocessNode(tree.children[i])
        if built then
            result[#result + 1] = built
        end
    end

    return {
        success = true,
        warnings = #self._warnings > 0 and self._warnings or nil,
        value = self:mergeTextNodes(result),
    }
end

---Performs parsing and returns a list of interpolate nodes.
---@return omi.interpolate.Result
function InterpolationParser:parse()
    return BaseParser.parse(self)
end

---Creates a new interpolation parser.
---@param text string
---@param options omi.interpolate.ParserOptions?
---@return omi.interpolate.Parser
function InterpolationParser:new(text, options)
    local this = BaseParser.new(self, text, options)
    ---@cast this omi.interpolate.Parser

    options = options or {}

    this._allowTokens = utils.default(options.allowTokens, true)
    this._allowAtExpr = utils.default(options.allowAtExpressions, true)
    this._allowFunctions = utils.default(options.allowFunctions, true)
    this._allowCharEntities = utils.default(options.allowCharacterEntities, true)

    return this
end


return InterpolationParser
