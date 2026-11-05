local ok, err = ndb.lookup(matches[2])
if not ok then svo.echof("%s", err) end
