local name = multimatches[2][2]

ndb.merge_discovery({{
  name = name,
}})

raiseEvent("NameDB got new data")