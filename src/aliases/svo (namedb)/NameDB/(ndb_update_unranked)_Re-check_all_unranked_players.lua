local count = #db:fetch(ndb.db.people, db:eq(ndb.db.people.xp_rank, -2))
if count >= 100 and not ndb.updateunranked then
  svo.echof("This requests %d unranked character records over HTTPS. Repeat to confirm.", count)
  ndb.updateunranked = true
  return
end
ndb.updateunranked = nil
ndb.refresh("unranked")
