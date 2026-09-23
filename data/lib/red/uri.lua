local proc = require "red/proc"

if PLATFORM == 'Windows' then
  return { -- no ideas
    { "^ircs?://.+", proc.irc },
    { "^gemini://.+", proc.gemini },
    { "^gophers?://.+", proc.gemini },
  }
end

-- Hold alt to skip uri methods
return {
  { "^https?://.+", "xdg-open %q" },
  { "%.jpg$", "xdg-open %q" },
  { "%.png$", "xdg-open %q" },
  { "%.pdf$", "xdg-open %q" },
  { "%.mp[34]$", "xdg-open %q" },
  { "%.avi$", "xdg-open %q" },
  { "%.mkv$", "xdg-open %q" },
  { "%.docx$", "xdg-open %q" },
  { "^ircs?://.+", proc.irc },
  { "^gemini://.+", proc.gemini },
  { "^gophers?://.+", proc.gemini },
}
