-- Makefile (GNU make and BSD make), on the basis of mc's
-- makefile.syntax: make variables, the directives of the line start,
-- the special targets, the autoconf @..@ substitutions and the
-- recipes (the lines of a real tab).
local scheme = require "red/syntax/scheme"

-- $(..) and ${..}, balanced for the same delimiter or to the end of
-- the line; "$$" is the escaped dollar
local function variable(ctx, txt, i)
  if txt[i] ~= '$' then
    return
  end
  if txt[i + 1] == '$' then
    return 2
  end
  local open = txt[i + 1]
  local close = open == '(' and ')' or (open == '{' and '}')
  if not close then
    return
  end
  local depth, j = 1, i + 2
  while txt[j] and txt[j] ~= '\n' do
    if txt[j] == open then
      depth = depth + 1
    elseif txt[j] == close then
      depth = depth - 1
      if depth == 0 then
        return j - i + 1
      end
    end
    j = j + 1
  end
  return j - i
end

-- the autoconf substitutions @foo@
local function autoconf(ctx, txt, i)
  if txt[i] ~= '@' then
    return
  end
  local j = i + 1
  while txt[j] and txt[j] ~= '\n' and txt[j] ~= ' ' and txt[j] ~= '\t' do
    if txt[j] == '@' then
      return j - i + 1
    end
    j = j + 1
  end
end

-- the directives of the line start (column 0): GNU make and BSD make
local direct = {
  define = true, endef = true, include = true, ifdef = true,
  ifndef = true, endif = true, ['if'] = true, ifeq = true,
  ifneq = true, ['else'] = true,
  ['.if'] = true, ['.elif'] = true, ['.else'] = true,
  ['.endif'] = true, ['.for'] = true, ['.endfor'] = true,
  ['.include'] = true, ['.undef'] = true,
}

local function directive(ctx, txt, i)
  if i > 1 and txt[i - 1] ~= '\n' then
    return
  end
  local n = {}
  local j = i
  while txt[j] and txt[j]:find('[%w_.]') do
    table.insert(n, txt[j])
    j = j + 1
  end
  if #n > 0 and direct[table.concat(n, '')] then
    return #n
  end
end

-- the make variables and continuations live in every context
local refs = {
  { '\\\n', col = scheme.operator },
  { variable, col = scheme.number },
  { autoconf, col = scheme.string },
}

local col = {
  col = scheme.default,
  keywords = {
    { "=", ":", col = scheme.operator },
    { ".PHONY", ".SUFFIXES", ".DEFAULT", ".PRECIOUS",
      ".INTERMEDIATE", ".SECONDARY", ".DELETE_ON_ERROR", ".IGNORE",
      ".LOW_RESOLUTION_TIME", ".SILENT", ".EXPORT_ALL_VARIABLES",
      ".NOTPARALLEL", ".NOEXPORT", col = scheme.lib, word = true },
    { directive, col = scheme.keyword },
    { variable, col = scheme.number },
    { autoconf, col = scheme.string },
    { '\\\n', col = scheme.operator },
  },
  { -- comment: from # to the end of the line
    start = '#',
    stop = '\n',
    col = scheme.comment,
  },
  { -- a recipe: the line starts with a real tab
    linestart = '\t',
    stop = '\n',
    spaces = '\n',
    keywords = refs,
    col = scheme.string,
  },
}

return col
