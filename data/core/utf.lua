local utf = {
}
utf.__index = utf

function utf.chars(b)
	local i = 1
	local s
	local res = {}
	local ff = sys.utf_next
	while i <= b:len() do
		s = i
		i = i + ff(b, i)
		table.insert(res,  b:sub(s, i - 1))
	end
	return res
end

function utf.codepoint(sym)
	return sys.utf_codepoint(sym)
end

function utf.new(s)
	local u
	if type(s) == 'string' then
		u = utf.chars(s)
	elseif type(s) == 'table' then
		u = s
	else
		u = {}
	end
	setmetatable(u, utf)
	return u
end

function utf:sub(s, e)
	local len = #self
	s = s or 1
	e = e or len
	if e < 0 then
		e = len + e + 1
	end
	if s <= 0 then s = 1 end
	if s >= len then s = len end
	if e <= 0 then e = 0 end
	if e >= len then e = len end
	local new = {}
	for i = s, e do
		table.insert(new, self[i])
	end
	return utf.new(new)
end

function utf:len()
	return #self
end

function utf:tostr()
	return table.concat(self, '')
end

function utf:iter()
	local i = 0
	return function()
		i = i + 1
		return self[i]
	end
end

function utf.next(str)
	local c, n = sys.utf_sym(str)
	return c, n
end

return utf
