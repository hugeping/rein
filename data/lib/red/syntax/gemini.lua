-- Gemtext (text/gemini): a line oriented format, so almost every rule
-- is a line start.  Nothing is nested: a preformatted block ends at the
-- first "```" anywhere.
local scheme = require "red/scheme"

local col = {
  col = scheme.default,
  { -- link line: "=> url [label]"
    linestart = '=>',
    stop = '\n',
    scol = scheme.keyword,
    col = scheme.number,
  },
  { -- heading: "# ", "## ", "### "
    linestart = '#',
    stop = '\n',
    col = scheme.lib,
  },
  { -- list item
    linestart = '* ',
    stop = '\n',
    scol = scheme.number,
    col = scheme.default,
  },
  { -- quote
    linestart = '> ',
    stop = '\n',
    col = scheme.comment,
  },
  { -- preformatted block: "```" with an optional alt text toggles it
    linestart = '```',
    stop = '```',
    col = scheme.string,
  },
}

return col
