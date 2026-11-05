svo.sk.observecuringset(matches[2])
if (matches[2] == "normal" and svo.conf.serverside and svo.conf.gagserverside)
    or (matches[2] == "slowcuring" and not svo.inslowcuringmode() and svo.conf.gagserverside) then
  svo.deleteLineP()
end