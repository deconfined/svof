setTriggerStayOpen("Channel history", 0)

ndb.merge_discovery(ndb.temp_name_list)

ndb.temp_name_list = nil

raiseEvent("NameDB got new data")