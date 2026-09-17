-- A proc extension: red/proc.lua loads every file of this directory and
-- merges the returned table into proc.
--
-- Edit is the acme(1) command: the argument is a sam(1) editing script
-- which is applied to the text of the window Edit is run in; run from a
-- menu it edits the window that menu belongs to.  The script may span
-- several lines when Edit is executed as a selection.  Output and errors
-- go to +Errors.
--
-- Implemented:
-- dot is the selection, or the null string at the cursor when there is
-- none, as in acme: "Edit /word/ s//W/" replaces the first match at the
-- current line and, since Edit leaves its result selected, repeating the
-- same command walks through the file (the empty regexp in s//W/ stands
-- for the last one).  A command without an address acts on dot alone, so
-- without a selection a bare s finds nothing, as in sam.
--
--   addresses  . #n n $ 0 /regexp/ ?regexp? and the compounds a1,a2
--              a1;a2 a1+n a1-n and a1 a2 (the + may be elided)
--   commands   a i c d s m t p = =# and the loops x y g v
--   regexps    as in regexp(6): . [] * + ? | () ^ $ \escapes and sam's
--              \n; an empty regexp means the last one used.  Compiled to
--              an NFA and simulated (a Pike VM), so a match is the
--              leftmost and then the longest one, as in sam, and there
--              is no exponential backtracking
--
-- Not implemented: the file/menu commands (e r w f b B n D X Y), the
-- mark and k, undo (u), q, !, braces, and sam's deferred multi-change
-- model: a command's changes are applied before the next one runs.

-- The app environment (data/core/api.lua) replaces the global error
-- with a reporter that draws the message on the screen and yields, so
-- that it cannot be caught.  Raise through the real error instead: the
-- script is wrapped in pcall and failures are reported in +Errors.
local raw_error = (getfenv and getfenv(0) or _G).error

local function script_error(msg)
  raw_error(msg, 0)
end

-- regexps -----------------------------------------------------------------

-- the rune at byte i of s (the empty string at the end)
local function rat(s, i)
  local len = utf.next(s, i)

  if len == 0 then
    return ''
  end
  return s:sub(i, i + len - 1)
end

-- nodes: lit any class bol eol cat alt rep grp
local function parse_re(src)
  local p = { src = src, i = 1, ngroups = 0 }

  local parse_alt

  local function parse_atom()
    local c = rat(p.src, p.i)

    if c == '' then
      script_error(string.format("bad regexp: %q", p.src))
    end
    p.i = p.i + #c
    if c == '.' then
      return { t = 'any' }
    elseif c == '^' then
      return { t = 'bol' }
    elseif c == '$' then
      return { t = 'eol' }
    elseif c == '(' then
      p.ngroups = p.ngroups + 1
      local n = p.ngroups
      local x = parse_alt()

      if rat(p.src, p.i) ~= ')' then
        script_error(string.format("missing ) in %q", p.src))
      end
      p.i = p.i + 1
      return { t = 'grp', n = n, x = x }
    elseif c == '[' then
      local neg = false
      local items = {}

      if rat(p.src, p.i) == '^' then
        neg = true
        p.i = p.i + 1
      end
      while true do
        local d = rat(p.src, p.i)

        if d == '' then
          script_error(string.format("bad class in %q", p.src))
        elseif d == ']' and #items > 0 then
          p.i = p.i + 1
          return { t = 'class', neg = neg, items = items }
        end
        p.i = p.i + #d
        if d == '\\' then
          d = rat(p.src, p.i)
          p.i = p.i + #d
          if d == 'n' then d = '\n' end
        end
        if rat(p.src, p.i) == '-' and rat(p.src, p.i + 1) ~= ']' then
          p.i = p.i + 1
          local e = rat(p.src, p.i)

          p.i = p.i + #e
          if e == '\\' then
            e = rat(p.src, p.i)
            p.i = p.i + #e
            if e == 'n' then e = '\n' end
          end
          table.insert(items, { a = d, b = e })
        else
          table.insert(items, { a = d, b = d })
        end
      end
    elseif c == '\\' then
      local d = rat(p.src, p.i)

      p.i = p.i + #d
      if d == 'n' then
        d = '\n'
      end
      return { t = 'lit', c = d }
    end
    return { t = 'lit', c = c }
  end

  local function parse_rep()
    local x = parse_atom()
    local c = rat(p.src, p.i)

    if c == '*' then
      p.i = p.i + 1
      return { t = 'rep', min = 0, x = x }
    elseif c == '+' then
      p.i = p.i + 1
      return { t = 'rep', min = 1, x = x }
    elseif c == '?' then
      p.i = p.i + 1
      return { t = 'rep', min = 0, max = 1, x = x }
    end
    return x
  end

  local function parse_cat()
    local a = parse_rep()

    while true do
      local c = rat(p.src, p.i)

      if c == '' or c == '|' or c == ')' then
        return a
      end
      a = { t = 'cat', a = a, b = parse_rep() }
    end
  end

  parse_alt = function()
    local a = parse_cat()

    while rat(p.src, p.i) == '|' do
      p.i = p.i + 1
      a = { t = 'alt', a = a, b = parse_cat() }
    end
    return a
  end
  local node = parse_alt()

  if rat(p.src, p.i) ~= '' then
    script_error(string.format("bad regexp: %q", p.src))
  end
  return { node = node, ngroups = p.ngroups, src = src }
end

-- the NFA program: ops char/any/class/adv/save/split/jmp/match -----------

local function slots_copy(s)
  local t = {}

  for k, v in pairs(s) do
    t[k] = v
  end
  return t
end

local function compile_re(ast, ngroups)
  local prog = {}

  local function emit(op)
    table.insert(prog, op)
    return #prog
  end

  local function node(n)
    if n.t == 'lit' then
      emit { op = 'char', c = n.c }
    elseif n.t == 'any' then
      emit { op = 'any' }
    elseif n.t == 'class' then
      emit { op = 'class', neg = n.neg, items = n.items }
    elseif n.t == 'bol' then
      emit { op = 'bol' }
    elseif n.t == 'eol' then
      emit { op = 'eol' }
    elseif n.t == 'cat' then
      node(n.a)
      node(n.b)
    elseif n.t == 'alt' then
      local sp = emit { op = 'split' }

      prog[sp].x = #prog + 1
      node(n.a)
      local jp = emit { op = 'jmp' }
      prog[sp].y = #prog + 1
      node(n.b)
      prog[jp].x = #prog + 1
    elseif n.t == 'rep' then
      if n.min == 1 and not n.max then -- +
        local top = #prog + 1

        node(n.x)
        local sp = emit { op = 'split', x = top }

        prog[sp].y = #prog + 1
      else
        local sp = emit { op = 'split' }

        prog[sp].x = #prog + 1
        node(n.x)
        if n.max ~= 1 then -- * loops, ? does not
          emit { op = 'jmp', x = sp }
        end
        prog[sp].y = #prog + 1
      end
    elseif n.t == 'grp' then
      emit { op = 'save', n = 2 * n.n }
      node(n.x)
      emit { op = 'save', n = 2 * n.n + 1 }
    end
  end

  -- unanchored search: try the pattern here (x), else take one rune (y)
  local sp = emit { op = 'split' }
  local adv = emit { op = 'adv' }

  emit { op = 'jmp', x = sp }
  prog[sp].y = adv
  local first = #prog + 1

  prog[sp].x = first
  emit { op = 'save', n = 0 }
  node(ast)
  emit { op = 'save', n = 1 }
  emit { op = 'match' }
  return { prog = prog, first = first, ngroups = ngroups }
end

-- add a thread and follow its epsilon transitions at pos, in priority
-- order (the first branch of a split goes first)
local function add_thread(re, list, seen, pc, slots, pos, text)
  local pending = {}

  local add
  add = function(pc2, slots2)
    while true do
      if seen[pc2] then
        break
      end
      seen[pc2] = true
      local op = re.prog[pc2]

      if not op then
        break
      elseif op.op == 'jmp' then
        pc2 = op.x
      elseif op.op == 'split' then
        table.insert(pending, { pc = op.y, slots = slots_copy(slots2) })
        pc2 = op.x
      elseif op.op == 'save' then
        slots2[op.n] = pos
        pc2 = pc2 + 1
      elseif op.op == 'bol' then
        if pos == 1 or text[pos - 1] == '\n' then
          pc2 = pc2 + 1
        else
          break
        end
      elseif op.op == 'eol' then
        if not text[pos] or text[pos] == '\n' then
          pc2 = pc2 + 1
        else
          break
        end
      else
        table.insert(list, { pc = pc2, slots = slots2 })
        break
      end
    end
    local p = table.remove(pending)

    if p then
      add(p.pc, p.slots)
    end
  end
  add(pc, slots)
end

local function class_hit(op, c)
  for _, r in ipairs(op.items) do
    if c >= r.a and c <= r.b then
      return true
    end
  end
  return false
end

-- run the program over text[from..upto]; the leftmost then longest match
local function vm_run(re, text, from, upto, anchored)
  local prog = re.prog
  local clist, best = {}
  local seen = {}

  upto = math.min(upto, #text + 1)
  if from > upto then
    return
  end
  if anchored then
    add_thread(re, clist, seen, re.first, {}, from, text)
  else
    add_thread(re, clist, seen, 1, {}, from, text)
  end
  local i = from
  while i <= upto do
    local nlist, nseen = {}, {}

    for _, th in ipairs(clist) do
      local op = prog[th.pc]

      if op.op == 'match' then
        local s, e = th.slots[0] or from, th.slots[1] or i

        if not best or s < best.s or (s == best.s and e > best.e) then
          best = { s = s, e = e, slots = th.slots }
        end
      else
        local c = text[i]
        local ok

        if op.op == 'char' then
          ok = c == op.c
        elseif op.op == 'any' then
          ok = c ~= nil and c ~= '\n'
        elseif op.op == 'class' then
          ok = c ~= nil and c ~= '\n' and class_hit(op, c) ~= op.neg
        elseif op.op == 'adv' then
          ok = c ~= nil
        end
        if ok then
          add_thread(re, nlist, nseen, th.pc + 1, slots_copy(th.slots),
            i + 1, text)
        end
      end
    end
    i = i + 1
    clist = nlist
    if #clist == 0 then
      break
    end
  end
  if best then
    local caps = {}

    for g = 1, re.ngroups do
      local s, e = best.slots[2 * g], best.slots[2 * g + 1]

      if s then
        caps[g] = { s, e }
      end
    end
    return best.s, best.e, caps
  end
end

-- the leftmost match at or after pos
local function re_find(re, text, pos, upto)
  return vm_run(re, text, pos, upto or #text + 1, false)
end

-- the match starting latest at or before pos (it may straddle pos)
local function re_find_back(re, text, pos)
  for s = math.min(pos, #text), 1, -1 do
    local ms, me, caps = vm_run(re, text, s, #text + 1, true)

    if ms then
      return ms, me, caps
    end
  end
end

local function re_compile(src)
  local ast = parse_re(src)
  local re = compile_re(ast.node, ast.ngroups)

  re.src = src
  return re
end

-- scripts -----------------------------------------------------------------

-- p: { src, i } is the parser; ctx: { w, frame, text, dot, changes }
-- spans are { s, e } with e exclusive, in rune positions 1..#text+1

local function peek(p)
  return rat(p.src, p.i)
end

local function skip_space(p)
  while true do
    local c = peek(p)

    if c == ' ' or c == '\t' then
      p.i = p.i + #c
    else
      break
    end
  end
end

local function line_end(p)
  local c = peek(p)

  return c == '' or c == '\n'
end

local function eol(p)
  skip_space(p)
  if peek(p) == '\n' then
    p.i = p.i + 1
  elseif peek(p) ~= '' then
    script_error(string.format("unexpected %q", peek(p)))
  end
end

-- the text on the lines after the command, ended by a line with a dot
local function lines_text(p)
  local out = {}

  if peek(p) == '\n' then
    p.i = p.i + 1
  end
  while true do
    local s = p.i

    while not line_end(p) do
      p.i = p.i + #peek(p)
    end
    local l = p.src:sub(s, p.i - 1)

    if p.i > #p.src then
      if l ~= '' then
        table.insert(out, l)
      end
      break
    end
    p.i = p.i + 1
    if l == '.' then
      break
    end
    table.insert(out, l)
  end
  if #out == 0 then
    return ''
  end
  return table.concat(out, '\n') .. '\n'
end

-- a delimited text: any printable non-alphanumeric is the delimiter;
-- with d given, the text is read up to d (the s replacement)
local function delimited(p, d)
  if not d then
    d = peek(p)
    if d == '' or d == '\n' or d:find('^%w$') then
      return nil
    end
    p.i = p.i + #d
  end
  local out = {}
  while true do
    local c = peek(p)

    if c == '' then
      break
    end
    p.i = p.i + #c
    if c == d then
      break
    elseif c == '\\' then
      local n = peek(p)

      if n == d then
        p.i = p.i + #n
        table.insert(out, d)
      elseif n == 'n' then
        p.i = p.i + #n
        table.insert(out, '\n')
      else
        table.insert(out, c)
      end
    else
      table.insert(out, c)
    end
  end
  return table.concat(out), d
end

local last_re

-- a regexp in /.../ or ?...?; nil if the text does not start with one
local function regexp(p)
  local c = peek(p)
  local s, d

  if c == '/' or c == '?' then
    s, d = delimited(p)
  else
    return nil
  end
  if s == '' then
    if not last_re then
      script_error("no previous regexp")
    end
    return last_re, d
  end
  last_re = re_compile(s)
  return last_re, d
end

local function text_of(ctx, s, e)
  return table.concat(ctx.text, '', s, math.max(s, e - 1))
end

-- the span of line nr starting at rune from
-- the n-th line at or after pos, as in acme's lineaddr (sign >= 0)
local function line_fore(ctx, nr, pos)
  local text = ctx.text
  local p, n

  if pos <= 1 then
    p, n = 1, 1
  else
    p = pos
    n = text[pos - 1] == '\n' and 1 or 0
  end
  while n < nr do
    if p > #text then
      return nil
    end
    if text[p] == '\n' then
      n = n + 1
    end
    p = p + 1
  end
  local q = p

  while text[q] and text[q] ~= '\n' do
    q = q + 1
  end
  return { s = p, e = text[q] and q + 1 or q }
end

-- the line at or before pos, as in acme's lineaddr (sign < 0)
local function line_back(ctx, nr, pos)
  local text = ctx.text
  local p = pos
  local n = 0

  while n < nr do
    if p <= 1 then
      n = n + 1
      if n ~= nr then
        return nil
      end
    elseif text[p - 1] == '\n' then
      n = n + 1
      if n ~= nr then
        p = p - 1
      end
    else
      p = p - 1
    end
  end
  local e = p

  if p > 1 then
    p = p - 1
  end
  while p > 1 and text[p - 1] ~= '\n' do
    p = p - 1
  end
  return { s = p, e = e }
end

-- the first rune of the line containing pos
local function line_start(ctx, pos)
  while pos > 1 and ctx.text[pos - 1] ~= '\n' do
    pos = pos - 1
  end
  return pos
end

-- the line number of rune pos
local function line_nr(ctx, pos)
  local n = 1

  for i = 1, math.min(pos, #ctx.text) - 1 do
    if ctx.text[i] == '\n' then
      n = n + 1
    end
  end
  return n
end

local function add_change(ctx, s, e, t)
  local runes = utf.chars(t)

  if not ctx.quiet then
    table.insert(ctx.changes, { s = s, e = e, t = runes })
  end
  return #runes
end

local function say(ctx, fmt, ...)
  if not ctx.quiet then
    ctx.frame:err(fmt, ...)
  end
end

local function cmd_dot(ctx, s, e)
  ctx.dot = { s = math.max(1, s), e = math.max(1, e) }
end

-- apply the collected changes and move dot along with them
local function apply(ctx)
  if #ctx.changes == 0 then
    ctx.changes = {}
    return
  end
  table.sort(ctx.changes, function(a, b)
    return a.s > b.s or a.s == b.s and a.e > b.e
  end)
  local dot = ctx.dot
  local ds, de = 0, 0
  for _, ch in ipairs(ctx.changes) do
    local d = #ch.t - (ch.e - ch.s)

    if ch.e <= dot.s then
      ds = ds + d
    end
    if ch.e <= dot.e then
      de = de + d
    end
    local out = {}

    for i = 1, ch.s - 1 do
      table.insert(out, ctx.text[i])
    end
    for _, c in ipairs(ch.t) do
      table.insert(out, c)
    end
    for i = ch.e, #ctx.text do
      table.insert(out, ctx.text[i])
    end
    ctx.text = out
    ctx.changed = true
  end
  cmd_dot(ctx, dot.s + ds, dot.e + de)
  ctx.changes = {}
end

-- the replacement text of an s command
local function substitute(ctx, repl, ms, me, caps)
  local out = {}
  local i = 1

  while i <= #repl do
    local c = rat(repl, i)

    if c == '&' then
      for k = ms, me - 1 do
        table.insert(out, ctx.text[k])
      end
      i = i + 1
    elseif c == '\\' then
      local n = rat(repl, i + 1)

      if n:find('^%d$') then
        local g = caps[tonumber(n)]

        if g then
          for k = g[1], g[2] - 1 do
            table.insert(out, ctx.text[k])
          end
        end
      elseif n ~= '' then
        table.insert(out, n) -- the backslash quotes the next char
      end
      i = i + 1 + #n
    else
      table.insert(out, c)
      i = i + #c
    end
  end
  return table.concat(out)
end

local command

-- an address: a1,a2 / a1;a2, or a single one
local function address(p, ctx, dot)
  local function simple()
    local c = peek(p)

    if c == '.' then
      p.i = p.i + 1
      return { s = dot.s, e = dot.e }
    elseif c == '$' then
      p.i = p.i + 1
      return { s = #ctx.text + 1, e = #ctx.text + 1 }
    elseif c == '#' then
      local n = 0

      p.i = p.i + 1
      while peek(p):find('^%d$') do
        n = n * 10 + tonumber(peek(p))
        p.i = p.i + 1
      end
      n = math.min(n, #ctx.text) + 1
      return { s = n, e = n }
    elseif c == '/' or c == '?' then
      local back = c == '?'
      local re = regexp(p)
      local s, e

      if back then
        s, e = re_find_back(re, ctx.text, dot.s)
        if not s then -- wrap around, as in sam
          s, e = re_find_back(re, ctx.text, #ctx.text)
        end
      else
        s, e = re_find(re, ctx.text, dot.e)
        if not s then
          s, e = re_find(re, ctx.text, 1, dot.e)
        end
      end
      if not s then
        script_error(string.format("%s: no match", re.src))
      end
      return { s = s, e = e }
    elseif c:find('^%d$') then
      local n = 0

      while peek(p):find('^%d$') do
        n = n * 10 + tonumber(peek(p))
        p.i = p.i + 1
      end
      if n == 0 then
        return { s = 1, e = 1 }
      end
      local l = line_fore(ctx, n, 1)

      if not l then
        script_error("line out of range")
      end
      return l
    end
  end

  -- a2 in a1+a2 / a1-a2: a line, a regexp or, with nothing, line 1
  local function relative(a1, step)
    local base = step > 0 and a1.e or a1.s

    if peek(p):find('^%d$') then
      local n = 0

      while peek(p):find('^%d$') do
        n = n * 10 + tonumber(peek(p))
        p.i = p.i + 1
      end
      local l = step > 0 and line_fore(ctx, n, base) or line_back(ctx, n, base)

      if not l then
        script_error("line out of range")
      end
      return l
    elseif peek(p) == '/' or peek(p) == '?' then
      local re = regexp(p)
      local s, e

      if step > 0 then
        s, e = re_find(re, ctx.text, base)
        if not s then -- wrap around, as in sam
          s, e = re_find(re, ctx.text, 1, base)
        end
      else
        s, e = re_find_back(re, ctx.text, base)
      end
      if not s then
        script_error(string.format("%s: no match", re.src))
      end
      return { s = s, e = e }
    end
    local l = step > 0 and line_fore(ctx, 1, base) or line_back(ctx, 1, base)

    if not l then
      script_error("line out of range")
    end
    return l
  end

  -- an address term: [+|-] followed by a line, a regexp or nothing
  local function term(base)
    local c = peek(p)

    if c == '+' or c == '-' then
      p.i = p.i + #c
      return relative(base, c == '+' and 1 or -1)
    end
    return simple()
  end

  -- a term with its + and - chain; the + may be elided before a line,
  -- a character address or a regexp, as in sam's simpleaddr
  local function chained(base)
    local a = term(base)

    while true do
      local c = peek(p)

      if c == '+' or c == '-' then
        p.i = p.i + #c
        a = relative(a, c == '+' and 1 or -1)
      else
        local save = p.i

        skip_space(p)
        if not a or not peek(p):find('^[/?#%d]') then
          p.i = save
          break
        end
        a = relative(a, 1)
      end
    end
    return a
  end

  local a1 = chained(dot)
  local c = peek(p)

  if c == ',' or c == ';' then
    local save = ctx.dot

    p.i = p.i + 1
    if c == ';' and a1 then
      ctx.dot = a1
    end
    local a2 = chained(a1 or dot)

    ctx.dot = save
    if a1 and a2 then
      return { s = a1.s, e = a2.e }
    elseif a2 then
      return { s = 1, e = a2.e }
    elseif a1 then
      return { s = a1.s, e = #ctx.text + 1 }
    end
    return { s = 1, e = #ctx.text + 1 }
  end
  return a1
end

-- one command; consumes through the end of its line
command = function(p, ctx, dot)
  local addr

  skip_space(p)
  addr = address(p, ctx, dot)
  local range = addr or dot
  local c

  skip_space(p)
  if range.s < 1 or range.e < range.s or range.e > #ctx.text + 1 then
    script_error("bad range")
  end
  c = peek(p)
  p.i = p.i + #c

  if c == '' or c == '\n' then
    cmd_dot(ctx, range.s, range.e)
    return
  elseif c == 'p' then
    say(ctx, "%s", text_of(ctx, range.s, range.e))
    cmd_dot(ctx, range.s, range.e)
  elseif c == '=' then
    local fname = tostring(ctx.w.buf.fname)
    local l1 = line_nr(ctx, range.s)
    local l2 = line_nr(ctx, range.e - 1)
    local mode = ''
    local t

    if peek(p) == '#' then
      p.i = p.i + 1
      mode = '#'
    elseif peek(p) == '+' then
      p.i = p.i + 1
      mode = '+'
    end
    if mode == '#' then
      t = string.format("%s:#%d", fname, range.s - 1)
      if range.e > range.s then
        t = t .. string.format(",#%d", range.e - 1)
      end
    elseif mode == '+' then
      local c1 = range.s - line_start(ctx, range.s)
      local c2 = (range.e - 1) - line_start(ctx, range.e - 1)

      t = string.format("%s:%d+#%d", fname, l1, c1)
      if l2 > l1 then
        t = t .. string.format(",%d+#%d", l2, c2)
      end
    else
      t = string.format("%s:%d", fname, l1)
      if l2 > l1 then
        t = t .. string.format(",%d", l2)
      end
    end
    say(ctx, "%s", t)
    cmd_dot(ctx, range.s, range.e)
  elseif c == 'a' or c == 'i' or c == 'c' then
    local t = delimited(p)
    local s, e

    if t == nil then
      t = lines_text(p)
      s, e = range.s, range.e
      if c == 'a' then
        s, e = range.e, range.e
      elseif c == 'i' then
        s, e = range.s, range.s
      end
    else
      eol(p)
      if c == 'a' then
        s, e = range.e, range.e
      elseif c == 'i' then
        s, e = range.s, range.s
      else
        s, e = range.s, range.e
      end
    end
    local n = add_change(ctx, s, e, t)

    cmd_dot(ctx, s, s + n)
  elseif c == 'd' then
    add_change(ctx, range.s, range.e, '')
    cmd_dot(ctx, range.s, range.s)
  elseif c == 's' then
    local count = 0
    local all = false
    local re, repl
    local d

    while peek(p):find('^%d$') do
      count = count * 10 + tonumber(peek(p))
      p.i = p.i + 1
    end
    if count == 0 then
      count = 1
    end
    re, d = regexp(p)
    if not re then
      script_error("s needs a regexp")
    end
    repl = delimited(p, d) or ''
    if peek(p) == 'g' then
      all = true
      p.i = p.i + 1
    end
    local pos = range.s
    local n = 0
    local op = -1
    local delta = 0
    local did
    while pos <= range.e do
      local ms, me, caps = re_find(re, ctx.text, pos, range.e)

      if not ms or me > range.e then
        break
      end
      if ms == me and ms == op then
        pos = ms + 1
      else
        pos = ms == me and ms + 1 or me
        op = me
        n = n + 1
        if n >= count then
          local t = substitute(ctx, repl, ms, me, caps)

          delta = delta + add_change(ctx, ms, me, t) - (me - ms)
          did = true
          if not all then
            break
          end
        end
      end
    end
    if not did then
      script_error(string.format("%s: no match", re.src))
    end
    cmd_dot(ctx, range.s, range.e + delta)
  elseif c == 'm' or c == 't' then
    local dest

    skip_space(p)
    dest = address(p, ctx, range)

    if not dest then
      script_error(string.format("%s needs an address", c))
    end
    local t = text_of(ctx, range.s, range.e)
    local n = #utf.chars(t)
    local d = dest.e

    if c == 't' then
      add_change(ctx, d, d, t)
    elseif not (dest.s == range.s and dest.e == range.e) then -- not self
      if d <= range.s or d >= range.e then
        add_change(ctx, d, d, t)
        add_change(ctx, range.s, range.e, '')
      else
        script_error("move overlaps itself")
      end
    end
    cmd_dot(ctx, d, d + n)
  elseif c == 'g' or c == 'v' then
    local re = regexp(p)

    if not re then
      script_error(string.format("%s needs a regexp", c))
    end
    local hit = re_find(re, ctx.text, range.s, range.e) ~= nil

    skip_space(p)
    if line_end(p) then
      script_error(string.format("%s needs a command", c))
    end
    local quiet = (c == 'v') ~= not hit

    ctx.quiet = quiet or ctx.quiet
    local ok, e = pcall(command, p, ctx, { s = range.s, e = range.e })

    ctx.quiet = nil
    if not ok then
      script_error(e)
    end
  elseif c == 'x' or c == 'y' then
    local re = regexp(p)
    local sub

    if not re then
      if c == 'y' then
        script_error("y needs a regexp")
      end
      re = re_compile('.*\\n')
    end
    skip_space(p)
    sub = not line_end(p)
    local save = p.i
    local spans = {}
    local pos = range.s
    local op = c == 'y' and range.s or -1
    while pos <= range.e do
      local ms, me = re_find(re, ctx.text, pos, range.e)

      if not ms or me > range.e then
        break
      end
      if ms == me and ms == op then
        pos = ms + 1
      else
        pos = ms == me and ms + 1 or me
        op = me
        table.insert(spans, { s = ms, e = me })
      end
    end
    if c == 'y' then
      local gaps = {}
      local prev = range.s

      for _, m in ipairs(spans) do
        table.insert(gaps, { s = prev, e = m.s })
        prev = m.e
      end
      table.insert(gaps, { s = prev, e = range.e })
      spans = gaps
    end
    for _, m in ipairs(spans) do
      p.i = save
      if sub then
        command(p, ctx, m)
      else
        say(ctx, "%s", text_of(ctx, m.s, m.e))
      end
      cmd_dot(ctx, m.s, m.e)
    end
    if #spans == 0 then
      if sub then -- parse the sub-command for its text only
        p.i = save
        ctx.quiet = true
        pcall(command, p, ctx, { s = range.s, e = range.s })
        ctx.quiet = nil
      end
      cmd_dot(ctx, range.s, range.s)
    end
  else
    script_error(string.format("unknown command: %q", c))
  end
  if p.i > 1 and rat(p.src, p.i - 1) ~= '\n' then
    eol(p)
  end
end

local function Edit(w, script)
  if type(script) ~= 'string' or script:strip() == '' then
    w.frame:err("Edit: no command")
    return true
  end
  local data = w:data() -- a menu edits the window it belongs to

  if not data then
    w.frame:err("Edit: no window")
    return true
  end
  w = data
  local ctx = {
    w = w,
    frame = w.frame,
    text = utf.chars(w:gettext() or ''),
    changes = {},
  }

  -- dot is the selection, or the null string at the cursor when there
  -- is none, as in acme; the selection may be made right to left
  if w.buf:issel() then
    local s, e = w.buf:selrange()

    ctx.dot = {
      s = math.max(1, math.min(s, #ctx.text + 1)),
      e = math.max(1, math.min(e, #ctx.text + 1)),
    }
  else
    local cur = math.max(1, math.min(w.buf.cur or 1, #ctx.text + 1))

    ctx.dot = { s = cur, e = cur }
  end
  local ok, err = pcall(function()
    local p = { src = script, i = 1 }

    while true do
      skip_space(p)
      local c = peek(p)

      if c == '' then
        break
      elseif c == '\n' then
        p.i = p.i + 1
      else
        command(p, ctx, ctx.dot)
        apply(ctx)
      end
    end
  end)
  if not ok then
    w.frame:err("Edit: %s", tostring(err))
  end
  if ctx.changed then
    -- replace the text as one buffer edit, so that undo takes the whole
    -- Edit back at once (the same way win:text_replace does it)
    w.buf:history 'start'
    w.buf:setsel(1, #w.buf.text + 1)
    w.buf:cut()
    w.buf:input(table.concat(ctx.text))
    w.buf:history 'end'
    w:dirty(true)
  end
  local s = math.max(1, math.min(ctx.dot.s, #w.buf.text + 1))
  local e = math.max(1, math.min(ctx.dot.e, #w.buf.text + 1))

  if e > s then
    w:setsel(s, e)
  end
  w:cur(e)
  if w.rows then
    w:visible()
  end
  return true
end

return {
  Edit = Edit,
}
