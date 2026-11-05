if isPrompt() then return end
local data = string.split(line, ", ")
data[#data] = string.sub(data[#data], 1, #data[#data] - 1)
if data[#data]:starts("and ") then data[#data] = data[#data]:match("and (%w+)") end
temp_name_list = {}
for _, name in ipairs(data) do temp_name_list[#temp_name_list + 1] = {name = name} end
