function xlat(n)
	if n >= 128 and n <= 159 then
		return n + 0x410 - 128
	end
	if n >= 160 and n <= 175 then
		return n + 0x430 - 160
	end
	if n >= 224 and n <= 239 then
		return 0x440 + n - 224
	end
	if n == 240 then return 0x401 end
	if n == 241 then return 0x451 end
	return n
end
local f = io.open("ESALT8X8.FNT", "r")
for i=0,255 do
	print(string.format("0x%04x", xlat(i)))
	for y = 1, 8 do
		local b = f:read(1)
		local r = ''
		b = string.byte(b)
		for i=1,8 do
			r = r .. ((b >= 128) and '#' or '-')
			if b >= 128 then b = b - 128 end
			b = b * 2
		end
		print(r)
	end
	print()
end
