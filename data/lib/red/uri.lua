local uri = {
  { "^https?://.+", "xdg-open %q" },
  { "%.jpg", "xdg-open %q" },
  { "%.png", "xdg-open %q" },
  { "%.pdf", "xdg-open %q" },
}

return uri
