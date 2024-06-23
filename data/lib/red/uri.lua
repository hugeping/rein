if PLATFORM == 'Windows' then
  return { -- no ideas
  }
end

return {
  { "^https?://.+", "xdg-open %q" },
  { "%.jpg$", "xdg-open %q" },
  { "%.png$", "xdg-open %q" },
  { "%.pdf$", "xdg-open %q" },
  { "%.mp[34]$", "xdg-open %q" },
  { "%.avi$", "xdg-open %q" },
  { "%.mvk$", "xdg-open %q" },
  { "%.docx$", "xdg-open %q" },
}
