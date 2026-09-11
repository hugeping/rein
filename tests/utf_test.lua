-- Tests for the Lua utf double used by the headless harness.
-- (Mirrors src/utf.c, so bugs here mean wrong test results elsewhere.)

describe("utf", function()
  it("chars splits ascii", function()
    eq(#utf.chars("abc"), 3)
    eq(utf.chars("abc")[2], "b")
  end)

  it("chars splits utf-8", function()
    local chars = utf.chars("a\208\177b") -- a + U+0431 + b
    eq(#chars, 3)
    eq(chars[2], "\208\177")
  end)

  it("len counts codepoints", function()
    eq(utf.len("abc"), 3)
    eq(utf.len("a\208\177b"), 3)
  end)

  it("next returns char length", function()
    eq(utf.next("abc", 1), 1)
    eq(utf.next("a\208\177b", 2), 2)
    eq(utf.next("abc", 9), 0)
  end)

  it("codepoint decodes", function()
    eq(utf.codepoint("A", 1), 65)
    local cp, len = utf.codepoint("\208\177", 1)
    eq(cp, 0x431)
    eq(len, 2)
  end)

  it("from_codepoint encodes", function()
    eq(utf.from_codepoint(65), "A")
    eq(utf.from_codepoint(0x431), "\208\177")
  end)
end)
