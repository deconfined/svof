if true then return end

--

local temp_name_list = {}

for key,value in pairs(citizens:split("|")) do
  temp_name_list[key] = {name = value}
end

ndb.merge_discovery(temp_name_list)

raiseEvent("NameDB got new data")