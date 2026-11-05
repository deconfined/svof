local temp_name_list = temp_name_list or {}

temp_name_list[#temp_name_list + 1] = {
  name = multimatches[2][2],
}

ndb.merge_discovery(temp_name_list)

raiseEvent("NameDB got new data")