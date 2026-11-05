if isPrompt() then return end
resetFormat()
local match = getColorWildcard(14)
if match then
  temp_name_list[#temp_name_list + 1] = {name = match[1]}
  local class = ndb.getclass(match[1])
  if class and class ~= "" then
    ndb.temp_classes_list[class] = (ndb.temp_classes_list[class] or 0) + 1
  end
end
