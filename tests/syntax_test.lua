local syntax = require "red/syntax"
local scheme = require "red/scheme"

local function colorize_text(text, scheme_name)
  local chars = utf.chars(text)
  local s = syntax.new(chars, 1, scheme_name)
  for i = 1, #chars do
    s:process(i, #chars)
  end
  return s, chars
end

describe("syntax", function()
  it("creates a colorizer for the lua scheme", function()
    local s = syntax.new(utf.chars("local x = 1"), 1, "lua")
    ok(s.ctx, "scheme context is loaded")
    ok(#s.txt > 0)
  end)

  it("takes a scheme only by a plain name", function()
    eq(syntax.scheme("c"), "c")
    eq(syntax.scheme("makefile"), "makefile")
    eq(syntax.scheme("../scheme"), nil)
    eq(syntax.scheme("../scheme.lua"), nil)
    eq(syntax.scheme("../../../core/core"), nil)
    eq(syntax.scheme("/c"), nil)
    eq(syntax.scheme("./c"), nil)
    eq(syntax.scheme("c/../c"), nil)
    eq(syntax.scheme("c.lua"), nil)
    eq(syntax.scheme("scheme"), nil)
    eq(syntax.scheme(""), nil)
    eq(syntax.scheme(nil), nil)
  end)

  it("processes a whole line without errors", function()
    local s, chars = colorize_text("local x = 1", "lua")
    ok(s.cols[1] ~= nil)
    ok(s.cols[#chars] ~= nil)
  end)

  it("colors a keyword differently from a plain identifier", function()
    local s = colorize_text("local xxx", "lua")
    ok(s.cols[1] ~= nil, "keyword colored")
    ok(s.cols[7] ~= nil, "identifier colored")
    ne(s.cols[1], s.cols[7], "keyword and identifier colors differ")
  end)

  it("handles a string literal", function()
    local s, chars = colorize_text('x = "hello"', "lua")
    for i = 1, #chars do
      ok(s.cols[i] ~= nil, "char " .. i .. " colored")
    end
  end)

  it("does not mutate the scheme keyword tables", function()
    local lua_scheme = require "red/syntax/lua"
    local keywords = lua_scheme.keywords[2]
    ok(type(keywords[2]) == "string", "keyword starts as a string")
    colorize_text("local x", "lua")
    eq(type(keywords[2]), "string", "keyword stays a string")
  end)

  it("colors a makefile: variables, directives, recipes", function()
    local s = colorize_text(
      "# make it\nCC = $(CC)\n\t$(CC) -o $$x\n", "makefile")
    eq(s.cols[1], scheme.comment, "comment")
    ne(s.cols[1], scheme.operator, "the comment is not the operator")
    ok(s.cols[14] == scheme.operator, "= operator")
    ok(s.cols[16] == scheme.number, "$(CC) variable")
    -- line 3 (from 22): the recipe with its variables
    ok(s.cols[22] == scheme.string, "the recipe line")
    ok(s.cols[23] == scheme.number, "$(CC) of the recipe")
  end)

  it("starts a makefile recipe only at a real tab", function()
    local s = colorize_text("ifeq ($(A),$(B))\n\ttrue\nendif\n", "makefile")
    eq(s.cols[1], scheme.keyword, "ifeq")
    ok(s.cols[18] == scheme.string, "the recipe of the tab")
    eq(s.cols[24], scheme.keyword, "endif")
  end)

  it("does not take an indented tab as a makefile recipe", function()
    local s = colorize_text(" \ttrue\n", "makefile")
    eq(s.cols[1], scheme.default, "the space is the default")
    eq(s.cols[2], scheme.default, "the tab too")
  end)

  it("a rule start at the end of the text is safe", function()
    ok(colorize_text("char *s = \"", "c"), "an unterminated string")
    ok(colorize_text("    s = \"\"\"", "python"), "three quotes")
    ok(colorize_text("head\n\n`", "markdown"), "a backtick")
    ok(colorize_text("all:\n\t", "makefile"), "a lonesome tab")
  end)
end)
