local scheme = require "red/syntax/scheme"

local function number(ctx, txt, i)
  local n = ''
  local start = i
  while txt[i] and txt[i]:find("[0-9]") do
    n = n .. txt[i]
    i = i + 1
  end
  if n ~= '' then return i - start end
  return false
end

local col = {
  col = scheme.default,
  keywords = {
    { "<-", "+", "&", "(", ")", "-", "|", "<", "[", "]", "*", "^",
      ">", "{", "}", "/", "=", ",", ";", "%", "!", ".", ":",
      col = scheme.operator },
    {
      "break", "case", "chan", "const", "continue", "default",
      "defer", "else", "fallthrough", "for", "func", "go",
      "goto", "if", "import", "interface", "map", "package",
      "range", "return", "select", "struct", "switch", "type",
      "var",
      col = scheme.keyword, word = true
    },
    {
      "uint8", "uint16", "uint32", "uint64", "int8",
      "int16", "int32", "int64", "float32", "float64",
      "byte", "uint", "int", "float", "uintptr",
      "string", "bool",

      "nil", "true", "false", "iota", "cap", "close",
      "closed", "len", "make", "new", "panic",
      "panicln", "print",
      col = scheme.lib, word = true,
    },
    {
      "tar", "zip", "bufio", "bytes", "cmd", "compress",
      "container", "crypto", "database", "debug", "encoding",
      "errors", "expvar", "flag", "fmt", "hash", "html",
      "image", "suffixarray", "race", "singleflight",
      "syscall", "testenv", "trace", "io", "log", "math",
      "mime", "net", "os", "path", "reflect", "regexp",
      "runtime", "sort", "strconv", "strings", "sync",
      "testing", "text", "time", "unicode", "unsafe",
      "vendor", "unicode", "functions", "init",
      col = scheme.lib, word = true,
    },
    { number, col = scheme.number },
  },
  { -- string
    start = "`",
    stop = "`",
    col = scheme.string,
  },
  { -- string
    start = '"',
    stop = '"',
    keywords = {
      { '\\"', '\\\\' },
    },
    col = scheme.string,
  },
  { -- string
    start = "'",
    stop = "'",
    keywords = {
      { "\\'", "\\\\" },
    },
    col = scheme.string,
  },
  { -- comment
    start = "/*";
    stop = '*/';
    col = scheme.comment,
  },
  { -- comment
    start = "//";
    stop = '\n';
    col = scheme.comment,
  },
}

return col
