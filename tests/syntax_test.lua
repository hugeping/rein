local syntax = require "red/syntax"

local function colorize_text(text, scheme)
  local chars = utf.chars(text)
  local s = syntax.new(chars, 1, scheme)
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
    local scheme = require "red/syntax/lua"
    local keywords = scheme.keywords[2]
    ok(type(keywords[2]) == "string", "keyword starts as a string")
    colorize_text("local x", "lua")
    eq(type(keywords[2]), "string", "keyword stays a string")
  end)
end)
