local scheme = require "red/syntax/scheme"

local function linkstart(ctx, txt, s, e)
  if txt[s] ~= '[' then
    return
  end
  local esc
  local link = false
  for i = s + 1, e do
    if esc then
      esc = false
    elseif txt[i] == '\\' then
      esc = true
    elseif not link then
      if txt[i] == ']' then
        link = true
      end
    elseif txt[i] ~= '(' then
      break
    else
      return i - s
    end
  end
end

local function endsect(ctx, txt, i)
  if txt[i] == '\n' and txt[i+1] ~= ' ' then
    return 1
  end
end

local function numbersect(ctx, txt, pos, epos)
  local n = ''
  for i = pos, epos do
    if txt[i]:find("[0-9]") then
      n = n .. txt[i]
    elseif txt[i] == '.' then
      if txt[i+1] ~= ' ' then return end
      break
    else
      return
    end
  end
  return n:len() + 1
end

local col = {
  col = scheme.default,
  keywords = {
    { '\\*', '\\#', '\\-', '\\\\', '\\`', '\\_',
      '\\(', '\\)', '\\[', '\\]' },
  },
  { -- section
    linestart = '#',
    stop = '\n',
    col = scheme.lib,
  },
  { -- strong
    start = '**',
    stop = '**',
    col = scheme.keyword,
    keywords = {
      { '\\*', '\\\\', },
    },
  },
  { -- items
    linestart = '* ',
    stop = endsect,
    scol = scheme.number,
    col = scheme.default,
  },
  { -- items
    linestart = '- ',
    stop = endsect,
    scol = scheme.number,
    col = scheme.default,
  },
  { -- items
    linestart = numbersect,
    stop = endsect,
    scol = scheme.number,
    col = scheme.default,
  },
  { -- quote
    linestart = '> ',
    stop = '\n',
    col = scheme.comment,
  },
  { -- code
    linestart = '    ',
    stop = '\n',
    col = scheme.string,
  },
  { -- code
    linestart = '```',
    stop = '```',
    col = scheme.string,
  },
  { -- code
    linestart = '~~~',
    stop = '~~~',
    col = scheme.string,
  },
  { -- inline code
    start = '`',
    stop = '`',
    col = scheme.string,
    keywords = {
      { '\\`', '\\\\', },
    },
  },
  { -- strong
    start = '*',
    stop = '*',
    col = scheme.keyword,
    keywords = {
      { '\\*', '\\\\', },
    },
  },

  { -- em
    start = '_',
    stop = '_',
    col = scheme.keyword,
    keywords = {
      { '\\_', '\\\\', },
    },
  },
  { -- link
    start = linkstart,
    stop = ')',
    col = scheme.number,
    keywords = {
      { '\\)', '\\]', '\\\\', },
    },
  },
  { -- comment
    start = '<!--',
    stop = '-->',
    col = scheme.comment,
  },

}

return col
