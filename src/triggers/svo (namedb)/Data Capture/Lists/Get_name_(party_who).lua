if isPrompt() then return end
resetFormat()
local name = ndb.findname(line)
if name then
  temp_name_list[#temp_name_list + 1] = {name = name}
  local class = ndb.getclass(name)
  if class and class ~= "" then
    echo((" "):rep(60 - #line))
    cecho("<a_darkwhite>(cached API: " .. class:title() .. ")")
    ndb.temp_classes_list[class] = (ndb.temp_classes_list[class] or 0) + 1
  end
end
