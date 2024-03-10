local blacklist = { [2322] = true, [3315] = true}
local exclude = "%%D0%%9E%%D0%%B1%%D0%%BD%%D0%%B0%%D0%%B6%%D0%%B5%%D0%%BD%%D0%%BA%%D0%%B0,%%D0%%A1%%D0%%B5%%D0%%BA%%D1%%81,%%D0%%A1%%D0%%B8%%D1%%81%%D1%%8C%%D0%%BA%%D0%%B8"
require "tiny"
local SLIDESHOW_DELAY = 4
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
  l = l:gsub("#", "%%23")
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
  local sk, e = sock.dial('zxart.ee', 80)
  if not sk then
    printf(0, 10, 16, "Error: "..e)
    return false, e
  end
  printf(0, 0, 16, "Connecting.")
  e = http_get(sk, string.format("/api/types:zxPicture/export:zxPicture/start:%d/limit:1/order:date,asc/filter:zxPictureType=standard;zxPictureTagsExclude="..(exclude or ''), cur))
  local json
  printf(0, 0, 16, "Connecting..")
  json, e = sk:read(e)
  if not json then
    sk:close()
    printf(0, 10, 16, "Error: %s", e)
    return false, e
  end
  printf(0, 0, 16, "Connecting...")
  local id = json_num(json, "id")
  total = json_num(json, "totalAmount")
  url = url_unesc(json_string(json, "originalUrl"))
  title = html_unesc(json_string(json, "title"))
  if blacklist[tonumber(id or -1)] then
    print("Blacklisted", 0, 10, 16)
    sk:close()
    return false, "Wrong data"
  end
  if not url or not total then
    print("No url", 0, 10, 16)
    sk:close()
    return false, "Wrong data"
  end
  print(fmt("%d/%d id:%d\n%s", cur+1, total, id, title), 0, title_y, 16, true)

  url = url:gsub("^https://zxart.ee", "")
  printf(0, 0, 16, "Connecting....")
  e = http_get(sk, url, true)
  if e ~= 6912 then
    print(fmt("Wrong data\n%s", url), 0, 10, 16, true)
    sk:close()
    return false, "Wrong data"
  end
  printf(0, 0, 16, "Connecting.....")
  local d = sk:read(e)
  sk:close()
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
clear(0)
gfx.fg(16)
gfx.bg(0)
print([[            ВНИМАНИЕ!!!!

Это приложение показывает картинки с внешнего ресурса http://zxart.ee!

Не смотря на то, что из выборки исключены соответствующие категории, некоторые изображения всё-таки могут содержать материалы недопустимые для просмотра детьми или носить оскорбительный характер!

Если вы столкнулись с подобными нежелательными картинками, вы можете сообщить их id для добавления в чёрный список.

  Автор rein: pkosyh@yandex.ru

Если вы готовы продолжить, нажмите z или пробел.

  Помощь:

стрелки/пробел/backspace - навигация
ввод - ввести номер картинки
z - слайд-шоу]], 0, 8, 15, true)
while sys.running() do
  local r, v = sys.input(true)
  if r == 'keydown' and (v == 'z' or v == 'x' or
    v == 'space' or v == 'return') then
    break
  end
  gfx.flip(1, true)
end
clear(0)
cur = 0
show()
local last = time()
local old = cur
local delta = 1
local slides

local function slide_note()
  clear(0, 256-8, 256, 8, 0)
  if slides then
    print("Slideshow", 192, 256 - 8, 2)
  end
end

while sys.running() do
  local r, v = inp()
  if r == 'keydown' then
    if slides then
      if v == 'z' or v == 'left' or v == 'right' or v == 'space'
        or v == 'backspace' or v == 'down' or v == 'up' or
        v == 'escape' then
        slides = false
      else
        last = -SLIDESHOW_DELAY
      end
    elseif v == 'right' or v == 'space' then
      cur = cur + delta
      delta = delta
    elseif v == 'left' or v == 'backspace' then
      cur = cur - delta
      delta = delta
    elseif v == 'down' then
      cur = cur + delta*10
      delta = delta + 1
    elseif v == 'up' then
      cur = cur - delta*10
      delta = delta + 1
    elseif v == 'return' then
      clear(0, title_y+32, 256, 8, 0)
      print("Number:", 0, title_y+32, 16)
      cur = (tonumber(inputln()) or cur+1) - 1
      clear(0, title_y+32, 256, 8, 0)
    elseif v == 'z' then -- slideshow
      slides = true
      last = -SLIDESHOW_DELAY;
    end
  end
  slide_note()
  cur = min(cur, total-1)
  cur = max(cur, 0)
  if slides and time() - last  > SLIDESHOW_DELAY then
    cur = rnd(total) - 1
    r = 'keyup'
  end
  if old ~= cur then
    clear(0, title_y, 256, 8, 0)
    printf(0,title_y,16, "%d/%d", cur + 1, total)
    if r == 'keyup' then
      delta = 1
      clear(0, 0, 256, 256-8, 0)
      dprint("get picture ".. tostring(cur))
      show()
      total = total or 0
      last = time()
      old = cur
    end
    slide_note()
  end
  flip(1, true)
end
