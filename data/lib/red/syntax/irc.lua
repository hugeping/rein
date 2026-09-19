-- IRC: red formats the log itself, so almost every rule is a line
-- start: "* ..." events and actions, "-nick- ..." notices and
-- "nick: ..." messages (a message to another channel is prefixed with
-- "[#chan] ").
local scheme = require "red/scheme"

-- "nick:" or "[#chan] nick:" at a line start; returns its length
local function nick(_, txt, pos, epos)
  local i = pos

  if txt[i] == '[' then -- "[#chan] nick:"
    while i <= epos do
      local c = txt[i]

      if not c or c == ' ' or c == '\n' then
        return
      end
      i = i + 1
      if c == ']' then
        break
      end
    end
    if txt[i] ~= ' ' then
      return
    end
    i = i + 1
  end
  local n = 0

  while i <= epos do
    local c = txt[i]

    if c == ':' then
      return n > 0 and (i - pos + 1) or nil
    end
    -- the usual nick characters plus "/": nicks of bridged networks
    -- look like "nick/matrix" or "nick/"
    if not c or not c:find('[%w_%[%]\\^{}`|/%-]') then
      return
    end
    n = n + 1
    i = i + 1
  end
end

return {
  col = scheme.default,
  { -- an event or an action: "* nick waves", "* 001 welcome"
    linestart = '*',
    stop = '\n',
    col = scheme.comment,
  },
  { -- a notice: "-srv- motd"
    linestart = '-',
    stop = '\n',
    col = scheme.operator,
  },
  { -- a message: "nick: text", "[#chan] nick: text"
    linestart = nick,
    stop = '\n',
    scol = scheme.number,
    col = scheme.default,
  },
}
