local pre = {
  {"%.[cC]$", { ts = 8, spaces_tab = false, trim_spaces = true } },
  {"%.lua$", { ts = 2, spaces_tab = true, trim_spaces = true } },
  {"%.md$", { ts = 2, spaces_tab = true } },
}
function pre.get(fname)
  for _, v in ipairs(pre) do
    if fname:find(v[1]) then
      return v[2]
    end
  end
end

return pre
