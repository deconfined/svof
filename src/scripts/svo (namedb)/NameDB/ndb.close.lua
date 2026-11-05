function ndb.close()
  ndb.cancel_lookups()
  db:close()
  ioprint("ndb.close sysExitEvent")
end