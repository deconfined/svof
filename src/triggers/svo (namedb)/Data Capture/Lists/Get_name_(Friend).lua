local match = getColorWildcard(14)
line = line:trim()
if match then
  temp_name_list[#temp_name_list + 1] = {name = match[1]}
  local class = ndb.getclass(match[1])
  if class and class ~= "" then
    echo((" "):rep(70 - #line))
    cecho("<a_darkwhite>(cached API: " .. class:title() .. ")")
    ndb.temp_classes_list[class] = (ndb.temp_classes_list[class] or 0) + 1
  end
end
