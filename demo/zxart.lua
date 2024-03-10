require "tiny"
local title_y = 256-60
local sock = require "sock"
local total = 0
local title = 0
local cur = 0
local pal = {
  [0] = { 0x00, 0x00, 0x00 },
  [1] = { 0x00, 0x00, 0xd8 },
  [2] = { 0xd8, 0x00, 0x00 },
  [3] = { 0xd8, 0x00, 0xd8 },
  [4] = { 0x00, 0xd8, 0x00 },
  [5] = { 0x00, 0xd8, 0xd8 },
  [6] = { 0xd8, 0xd8, 0x00 },
  [7] = { 0xd8, 0xd8, 0xd8 },

  [8] = { 0x00, 0x00, 0x00 },
  [9] = { 0x00, 0x00, 0xff },
  [10] = { 0xff, 0x00, 0x00 },
  [11] = { 0xff, 0x00, 0xff },
  [12] = { 0x00, 0xff, 0x00 },
  [13] = { 0x00, 0xff, 0xff },
  [14] = { 0xff, 0xff, 0x00 },
  [15] = { 0xff, 0xff, 0xff },
}

--local colors

local function bank(nr, buf)
  local attr = 0x1800
  local y = nr*64
  for yy=0, 7 do
    local pa = attr + (nr*8 + yy)*32
    local p = nr*2048 + 32*yy
    for i = 0, 7 do
      for xx = 0, 31 do
        local b = buf:byte(p + 1)
        p = p + 1
        local a = buf:byte(pa + xx + 1)
        local br = (bit.band(a,0x40) == 0x40) and 8 or 0
        local fg = pal[bit.band(a, 0x7) + br]
        local bg = pal[bit.band(bit.rshift(a, 3), 0x7) + br]
        for s = 0, 7 do
            if bit.band(b, bit.rshift(0x80, s)) ~= 0 then
              pixel(xx*8+s, y + yy*8+i, fg)
            else
              pixel(xx*8+s, y + yy*8+i, bg)
            end
        end
      end
      p = p + 256 - 32
    end
  end
end

local function http_resp(sk)
  local len = 0
  while true do
    local l = sk:readln(true)
    if not l or l:empty() then
      break
    end
    if l:startswith("Content-Length:") then
      len = tonumber(l:sub(16):strip())
    end
  end
  return len
end

local function http_get(sk, req, close)
  sk:println("GET %s HTTP/1.1", req)
  sk:println("Host: zxart.ee")
  if close then
    sk:println("Connection: close")
  end
  sk:println()
  return http_resp(sk)
end

local function url_unesc(l)
  if not l then return l end
  l = l:gsub("\\?[/\\]", { ['\\\\'] = '\\', ['\\/'] = '/' })
  l = l:gsub("#([0-9]+);", function(s)
    return string.char(tonumber(s))
  end)
  return l
end

local function html_unesc(l)
  if not l then return l end
  l = l:gsub("&[^&]+;", { ['&amp;'] = '&', ['&quot;'] = '"'})
  l = l:gsub("\\u([0-9a-f][0-9a-f][0-9a-f][0-9a-f])", function(s)
    return utf.from_codepoint(tonumber(s, 16));
  end)
  l = l:gsub('&#([0-9]+);', function(s)
    return string.char(tonumber(s))
  end)
  return l
end

local function json_string(json, name)
  name = '"'..name..'":'
  if not json:find(name, 1, true) then
    return false
  end
  return json:gsub('^.*'..name..'"([^"]+)".*$', "%1")
end

local function json_num(json, name)
  name = '"'..name..'":'
  if not json:find(name, 1, true) then
    return false
  end
  return json:gsub('^.*'..name..'([0-9]+).*$', "%1")
end

local function get_pict()
  nr = nr or 0
  fill_rect(0, 0, 256, 256, 0)
  local sk, e = sock.dial('zxart.ee', 80)
  if not sk then
    printf(0, 10, 16, "Error: "..e)
    return false, e
  end
  printf(0, 0, 16, "Connecting.")
  e = http_get(sk, string.format("/api/types:zxPicture/export:zxPicture/start:%d/limit:1/order:date,asc/filter:zxPictureType=standard;", cur))
  local json
  printf(0, 0, 16, "Connecting..")
  json, e = sk:recv(e, true)
  if not json then
    printf(0, 10, 16, "Error: "..e)
    return json, e
  end
  printf(0, 0, 16, "Connecting...")
  total = json_num(json, "totalAmount")
  url = url_unesc(json_string(json, "originalUrl"))
  title = html_unesc(json_string(json, "title"))

  if not url then
    print("No url", 0, 10, 16)
    return false, "Wrong data"
  end
  print(fmt("%d/%d\n%s", cur+1, total, title), 0, title_y, 16, true)

  url = url:gsub("^https://zxart.ee", "")
  printf(0, 0, 16, "Connecting....")
  e = http_get(sk, url, true)
  if e ~= 6912 then
    print(fmt("Wrong data\n%s", url), 0, 10, 16, true)
    return false, "Wrong data"
  end
  printf(0, 0, 16, "Connecting.....")
  local d = sk:recv(e, true)
  if not d or d:len() ~= 6912 then
    printf(0, 10, 16, "No data")
    return false, "No data"
  end
  return d
end

local function show()
  local f, e = get_pict()
  if not f then return f, e end
  bank(0, f);
  bank(1, f);
  bank(2, f);
  return true
end
border(0)
gfx.fg(16)
gfx.bg(0)
cur = 14000-1
show()
local old = cur
local delta = 1
while sys.running() do
  local r, v
  r, v = inp()
  if r == 'text' and v == 'z' then r, v = 'keydown', 'return' end
  if r == 'keydown' then
    if v == 'right' then
      cur = cur + delta
      delta = delta
    elseif v == 'left' then
      cur = cur - delta
      delta = delta
    elseif v == 'down' then
      cur = cur + delta*10
      delta = delta + 1
    elseif v == 'up' then
      cur = cur - delta*10
      delta = delta + 1
    elseif v == 'return' then
      fill_rect(0, title_y+32, 255, title_y + 32+7, 0)
      print("Number:", 0, title_y+32, 16)
      cur = (tonumber(inputln()) or cur+1) - 1
      fill_rect(0, title_y+32, 255, title_y + 32+7, 0)
    end
  end
  cur = min(cur, total-1)
  cur = max(cur, 0)
  if old ~= cur then
    fill_rect(0, title_y, 255, title_y + 7, 0)
    printf(0,title_y,16, "%d/%d", cur + 1, total)
    if r == 'keyup' then
      delta = 1
      show()
      old = cur
    end
  end
  flip(1, true)
end
