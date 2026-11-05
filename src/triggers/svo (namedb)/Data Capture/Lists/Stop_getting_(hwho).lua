setTriggerStayOpen("NameDB hwho", 0)

ndb.merge_discovery(temp_name_list)

for _, person in pairs(temp_name_list) do
  raiseEvent("NameDB saw list name", person.name)
end

temp_name_list = nil

raiseEvent("NameDB got new data")