return {
  {"%.[cChH]$",
    { ts = 8,
      spaces_tab = false,
      trim_spaces = true,
      syntax = "c"
    }
  },
  {"%.cpp$",
    { ts = 8,
      spaces_tab = false,
      trim_spaces = true,
      syntax = "c"
    }
  },
  {"%.lua$",
    { ts = 2,
      spaces_tab = true,
      trim_spaces = true,
      syntax = "lua"
    }
  },
  {"%.go$",
    { ts = 8,
      spaces_tab = false,
      trim_spaces = true,
      syntax = "go",
    }
  },
  {"%.py$",
    { ts = 4,
      spaces_tab = true,
      trim_spaces = true,
      syntax = "python",
    }
  },
  {"%.md$", { ts = 2,
      spaces_tab = true,
      trim_spaces = true,
      syntax = "markdown",
      wrap = true
    }
  },
  {"%.diff$", { ts = 8,
    spaces_tab = false,
    trim_spaces = false,
    syntax = "diff"
    }
  },
  {"%.patch$", { ts = 8,
    spaces_tab = false,
    trim_spaces = false,
    syntax = "diff"
    }
  },
  {"/$", { ts = 8,
    spaces_tab = false,
    trim_spaces = false,
    syntax = "dir"
    }
  },
}
