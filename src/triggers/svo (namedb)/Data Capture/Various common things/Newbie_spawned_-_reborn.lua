local temp_name_list = {{name = matches[2]}}

ndb.merge_discovery(temp_name_list)

raiseEvent("NameDB got new data")