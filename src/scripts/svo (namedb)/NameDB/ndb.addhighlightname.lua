function ndb.addhighlightname(_, name)
  if _ == "NameDB facts reset" then
    if ndb.loadhighlights then ndb.loadhighlights() end
    return
  end
  if not name then return end -- no name is passed on a suicided person

  local person = ndb.getname(name)

  if not person then
    if ndb.highlightIDs and ndb.highlightIDs[name] then
      killTrigger(ndb.highlightIDs[name])
      ndb.highlightIDs[name] = nil
    end
    return
  end
  ndb.singlehighlight(name,
      person.city or "", 
      person.order or "", 
      person.cityenemy or 0,
      person.orderenemy or 0, 
      person.houseenemy or 0, 
      svo.me.watchfor[person.name],
      person.immortal or 0)
end