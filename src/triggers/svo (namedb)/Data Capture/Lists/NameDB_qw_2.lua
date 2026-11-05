ndb.merge_discovery(temp_name_list or {})
for _, person in ipairs(temp_name_list or {}) do
  raiseEvent("NameDB saw list name", person.name)
end
raiseEvent("NameDB got new data")
disableTrigger("NameDB qw")
disableTrigger("NameDB qw 2")
