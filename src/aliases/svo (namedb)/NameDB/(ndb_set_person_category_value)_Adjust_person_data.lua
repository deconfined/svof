local name, err = ndb.canonical_name(matches[2])
if not name then svo.echof("%s", err); return end
local category = matches[3]
if not ndb.policy_fields[category] then
  svo.echof("Character facts are API-owned. Editable fields: notes, iff, importance, cityenemy, houseenemy, orderenemy.")
  return
end
local value = matches[4]
if category == "notes" then value = value:gsub([[\n]], "\n")
elseif category == "iff" then
  value = tonumber(value)
  if value ~= -1 and value ~= 1 and value ~= 2 then svo.echof("IFF: -1 automatic, 1 enemy, 2 ally."); return end
elseif category == "importance" then
  value = tonumber(value)
  if not value or value ~= value or value == math.huge or value == -math.huge then return end
else value = svo.toboolean(value) and 1 or 0 end
ndb.merge_discovery({{name = name, [category] = value}})
ndb.showwhois(name)
raiseEvent("NameDB set name changed", name)
