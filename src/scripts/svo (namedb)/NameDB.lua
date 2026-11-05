-- The module priority this group used to set on install has no meaning in a
-- single package: load order comes from where these items sit in the tree.

ndb = ndb or {}
if ndb.honorsid then killTimer(ndb.honorsid); ndb.honorsid = nil end
if ndb.honorseqgag then killTrigger(ndb.honorseqgag); ndb.honorseqgag = nil end
if ndb.autochecklabel then ndb.autochecklabel:hide(); ndb.autochecklabel = nil end
ndb.honorslist, ndb.honorsname, ndb.gaghonours, ndb.manualcheck = nil, nil, nil, nil
-- Retire writable identity APIs on hot reload as well as on fresh installs.
for _, key in ipairs({"honors", "cancelhonors", "updatebyhonors", "honors_next",
  "finished_honors", "getinfo", "setfromclass", "setclass", "setdragon",
  "setmark", "setinfamous", "showhonorswindow", "hidehonorswindow", "showqwi", "showinfamous"}) do
  ndb[key] = nil
end

svo = svo or {}
