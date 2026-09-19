local scheme = require "red/scheme"

local col = {
  col = scheme.default,
  keywords = {
    { ":", ".", ">", "<", "+", "-", "*", "/", "%", "=",
      "!=", "==", "{", "}", "(", ")", "[", "]", ",", ";",
      col = scheme.operator },
    { "self", "and", "as", "assert", "async", "await", "break", "class",
      "continue", "def", "del", "elif", "else", "except",
      "exec", "finally", "for", "from", "global", "if",
      "import", "in", "is", "lambda", "nonlocal", "not", "or",
      "pass", "print", "raise", "return", "try", "while", "with",
      "yield", col = scheme.keyword, word = true
    },
    {
      "abs", "all", "any", "basestring", "bin", "bool",
      "callable", "chr", "classmethod",  "cmp", "coerce",
      "compile", "complex", "delattr", "dict", "dir",
      "divmod", "enumerate", "eval", "execfile", "file",
      "filter", "float", "frozenset", "getattr", "globals",
      "hasattr", "hash", "help", "hex", "id", "input",
      "int", "isinstance", "issubclass", "iter", "len",
      "list", "locals", "long", "map", "max", "min", "next",
      "object", "oct", "open", "ord", "pow", "print", "property",
      "range", "raw_input", "reduce", "reload", "repr",
      "reversed", "round", "setattr", "slice", "sorted",
      "staticmethod", "str", "sum", "super", "tuple",
      "type",  "unichr", "unicode", "vars", "xrange", "zip",

      "atof", "atoi", "atol", "expandtabs", "find", "rfind",
      "index", "rindex", "count", "split", "splitfields",
      "join", "joinfields", "strip", "lstrip", "rstrip",
      "swapcase", "upper", "lower", "ljust", "rjust", "center",
      "zfill",
      "__init__", "__del__", "__repr__", "__str__", "__cmp__",
      "__hash__", "__call__", "__getattr__", "__setattr__",
      "__delattr__", "__len__", "__getitem__", "__setitem__",
      "__delitem__", "__getslice__", "__setslice__",
      "__delslice__", "__add__", "__sub__", "__mul__",
      "__div__", "__mod__", "__divmod__", "__pow__", "__lshift__",
      "__rshift__", "__and__", "__xor__", "__or__", "__neg__",
      "__pos__", "__abs__", "__invert__", "__nonzero__", "__coerce__",
      "__int__", "__long__", "__float__", "__oct__", "__hex__",
      "__radd__", "__rsub__", "__rmul__", "__rdiv__", "__rmod__",
      "__rdivmod__", "__rpow__", "__rlshift__", "__rrshift__",
      "__rand__", "__rxor__", "__ror__",
      col = scheme.lib, word = true
    },
    { scheme.rule.digits, col = scheme.number },
  },
  scheme.rule.string '"""',
  scheme.rule.string "'''",
  scheme.rule.string '"',
  scheme.rule.string "'",
  scheme.rule.line_comment '#',
}

return col
