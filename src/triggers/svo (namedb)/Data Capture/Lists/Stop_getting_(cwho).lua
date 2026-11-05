setTriggerStayOpen("NameDB cwho", 0)

ndb.merge_discovery(temp_name_list)

for _, person in pairs(temp_name_list) do
  raiseEvent("NameDB saw list name", person.name)
end

if next(ndb.temp_classes_list) then
  local classes = svo.keystolist(ndb.temp_classes_list)
  table.sort(classes)

  for i = 1, #classes do
    classes[i] = ndb.temp_classes_list[classes[i]] .. " "..(ndb.temp_classes_list[classes[i]] == 1 and classes[i] or string.pluralize(classes[i]))
  end

  moveCursor(0, getLineNumber())
  svo.itf("Cached API classes: %s (%s names total).\n", svo.concatand(classes), #temp_name_list)
  moveCursorEnd()
  ndb.temp_classes_list = nil
end


temp_name_list = nil

raiseEvent("NameDB got new data")