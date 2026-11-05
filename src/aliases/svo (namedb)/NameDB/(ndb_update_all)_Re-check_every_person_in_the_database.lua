local count = #db:fetch(ndb.db.people)
if count >= 100 and not ndb.updateall then
  svo.echof("This requests %d character records over HTTPS. Repeat to confirm.", count)
  ndb.updateall = true
  return
end
ndb.updateall = nil
ndb.refresh("all")
