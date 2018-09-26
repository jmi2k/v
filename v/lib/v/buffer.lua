local class = require('oop-system').class

local Buffer = class('Buffer')
local unicode = require('unicode')
local math = require('math')

local function toLines(str)
    local t = {}
    local function helper(line) table.insert(t, line) return "" end
    helper((str:gsub("(.-)\r?\n", helper)))
    return t
end

function Buffer:init(text, term, size, gpu)
    local lines = toLines(text)
    self.lines = lines
    self.term = term
    self.lineNumbers = false
    self.scroll = {x = 0, y = 0}
    self.cursor = {x = 1, y = 1}
    self.size = size
    self.mode = nil
    self.prompt = ':'
    self.status = nil
    self.tempStatus = nil
    self.gpu = gpu
    self.modified = false
end

function Buffer:getData()
    return table.concat(self.lines, "\n")
end

-- The pair of 'startY' and 'endY' is the range of screen to be
-- updated, defaulted to the entire screen.
function Buffer:update(startY, endY)
    startY = startY or 1
    endY   = endY   or self.size.h - 1
    self.lineNumberLength = 0
    if self.lineNumbers then
        for i = startY, endY do
            self.term.setCursor(1, i)
            self.term.clearLine()
            if i + self.scroll.y <= #self.lines then
                local string = tostring(i + self.scroll.y)
                self.lineNumberLength = #string
                self.term.write(string, false)
            end
        end
    end

    for i = startY, endY do
        self:drawLine(i + self.scroll.y)
    end
    self:updateCursor()
end

function Buffer:drawLine(linenum)
    local w = self.size.w
    local start = 1
    if self.lineNumbers then
        w = w - (self.lineNumberLength + 1)
        start = start + self.lineNumberLength + 1
    end
    self.term.setCursor(start, linenum - self.scroll.y)
    self.term.write("\27[K") -- clear line from cursor right
    if linenum <= #self.lines then
        self.term.write(self.lines[linenum]:sub(self.scroll.x))
    end
end

function Buffer:readLine()
    self.mode = 'command'
    self.term.setCursor(1, self.size.h)
    self.term.clearLine()
    self.term.write(self.prompt)
    self.term.setCursor(1 + #self.prompt, self.size.h)
    local line = self.term.read(nil, false)
    self.mode = nil
    self.term.setCursorBlink(false)
    self:updateCursor()
    return line
end

function Buffer:setStatus(message)
    self.term.setCursor(1, self.size.h)
    self.term.clearLine()
    self.term.write(message)
    self:updateCursor()
end

function Buffer:moveCursor(x, y)
    local c = self.cursor
    c.x = c.x + x
    c.y = c.y + y
    self:verifyCursor()
end

function Buffer:setCursor(x, y)
    self.cursor.x = x
    self.cursor.y = y
    self:verifyCursor()
end

function Buffer:verifyCursor()
    local c = self.cursor
    c.x = math.max(c.x, 1)
    c.y = math.max(c.y, 1)
    c.y = math.min(c.y, #(self.lines))
    c.x = math.min(c.x, #(self.lines[c.y + self.scroll.y]) + ((self.mode == 'insert') and 1 or 0))
    self:updateCursor()
end

function Buffer:updateCursor()
    local c = self.cursor
    -- TODO: update self.scroll
    self.term.setCursor(c.x, c.y)
end

-- Insert a string at the current position of cursor. 'str' is a
-- sequence of printable characters.
function Buffer:insert(str)
    local c = self.cursor
    local linenum = c.y + self.scroll.y
    local line = self.lines[linenum]
    local index = c.x + self.scroll.x
    self.lines[linenum] =
        unicode.sub(line, 1, index - 1)..str..unicode.sub(line, index)
    self.modified = true
    self:update(c.y, c.y)
    self:moveCursor(unicode.len(str), 0)
end

-- Break a line at the current position of cursor.
function Buffer:newline()
    local c = self.cursor
    local linenum = c.y + self.scroll.y
    local line = self.lines[linenum]
    local index = c.x + self.scroll.x
    self.lines[linenum] = unicode.sub(line, 1, index - 1)
    table.insert(self.lines, linenum + 1, unicode.sub(line, index))
    self.modified = true
    if self.lineNumbers then
        -- Inserting a line may invalidate the calculated width of
        -- line numbers. We need to do a full redraw.
        self:update()
    else
        -- Only a partial redraw starting from the cursor position
        -- should suffice.
        self:update(c.y)
    end
    self:setCursor(1, c.y + 1)
end

Buffer.setTempStatus = Buffer.setStatus

return Buffer
