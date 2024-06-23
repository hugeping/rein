local scheme = require "red/syntax/scheme"

local function match(ext)
  if type(ext) ~= 'table' then
    ext = { ext }
  end
  return function(ctx, txt, i)
    local d = 0
    local n = {}
    while txt[i] ~= '\n' and txt[i] do
      table.insert(n, txt[i])
      i = i + 1
     end
     local t = table.concat(n, '')
     for _, v in ipairs(ext) do
       if (t:lower()):find(v, 1) then
         return #n
       end
     end
  end
end

local col = {
  col = scheme.default,
  {
    start = match("/$"),
    stop = '\n',
    col = scheme.number,
  },
  {
    start = match { "%.pdf$", "%.docx?$", "%.rtf$" },
    stop = '\n',
    col = scheme.keyword,
  },
  {
    start = match { "%.log$", "%.txt$", "%.md$" },
    stop = '\n',
    col = scheme.string,
  },
  {
    start = match { "%.jpe?g$", "%.gif$", "%.tiff$", "%.png", "%.xmp",
      "%.mp[34]$", "%.avi$", "%.mpeg$", "%.mkv$", "%.webm" },
    stop = '\n',
    col = scheme.operator,
  },
  {
    start = match { "%.zip$", "%.gz$", "%.rar$", "%.arj", "%.tar$" },
    stop = '\n',
    col = scheme.lib,
  },
}

return col
