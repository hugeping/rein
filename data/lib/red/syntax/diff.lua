local scheme = require "red/syntax/scheme"

local col = {
  col = scheme.default,
  {
    linestart = 'diff ',
    stop = '\n',
    col = scheme.number,
  },
  {
    linestart = 'index ',
    stop = '\n',
    col = scheme.number,
  },
  { -- section
    linestart = '--- ',
    stop = '\n',
    col = scheme.lib,
  },
  { -- section
    linestart = '+++ ',
    stop = '\n',
    col = scheme.lib,
  },
  { -- add
    linestart = '+',
    stop = '\n',
    col = { 0, 190, 0 },
  },
  { -- add
    linestart = '>',
    stop = '\n',
    col = { 0, 190, 0 },
  },
  { -- del
    linestart = '-',
    stop = '\n',
    col = {255, 0, 0 },
  },
  { -- del
    linestart = '<',
    stop = '\n',
    col = {255, 0, 0 },
  },
  {
    linestart = '@@ ',
    stop = '\n',
    col = scheme.string,
  }
}

return col
