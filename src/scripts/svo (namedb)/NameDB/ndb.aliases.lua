function ndb.showwhois(whom)
  local name, err = ndb.canonical_name(whom)
  if not name then svo.echof("%s", err); return end
  local data = ndb.getname(name)
  if not data then
    ndb.lookup(name)
    svo.echof("Looking up %s over HTTPS; use whois %s after completion.", name, name)
    return
  end
  local function known(value)
    if value == "" or value == nil or value == -1 then return "unknown" end
    return tostring(value)
  end
  svo.echof("%s — NameDB (%s)", name,
    data.api_verified == 1 and ("official API, " .. os.date("%Y-%m-%d %H:%M", data.api_updated)) or "facts unknown")
  echo("  Full name: " .. known(data.title) .. "\n")
  echo("  Class: " .. known(data.class) .. "  City: " .. known(data.city) .. "  House: " .. known(data.guild) .. "\n")
  echo("  Level: " .. known(data.level) .. "  XP rank: " .. (data.xp_rank == -2 and "unranked" or known(data.xp_rank)) .. "\n")
  echo("  Mob kills: " .. known(data.mob_kills) .. "  Player kills: " .. known(data.player_kills) ..
    "  Explorer rank: " .. known(data.explorer_rank) .. "\n")
  echo("  Gender, race, order, city rank/soldier, dragon, immortal, mark,\n")
  echo("  infamy, might, combat rank, birth, arms, divorces, motto and warcry:\n")
  echo("  unknown (not supplied by the official API).\n")
  echo("  Personal policies: IFF " .. (data.iff == 1 and "enemy" or data.iff == 2 and "ally" or "automatic") ..
    ", effective " .. (ndb.isenemy(name) and "enemy" or "not enemy") .. ", importance " .. data.importance .. "\n")
  echo("  City enemy: " .. (data.cityenemy == 1 and "yes" or "no") ..
    "  House enemy: " .. (data.houseenemy == 1 and "yes" or "no") ..
    "  Order enemy: " .. (data.orderenemy == 1 and "yes" or "no") .. "\n")
  cecho("  Notes: " .. (data.notes ~= "" and data.notes or "none") .. "\n")
  resetFormat()
  echoLink("Edit notes", ("printCmdLine(%q)"):format("ndb set " .. name .. " notes " .. data.notes:gsub("\n", [[\n]])),
    "Edit personal notes; API refreshes never replace these.", true)
  echo("\n")
  svo.showprompt()
end

function ndb.exportmenu()
  svo.echof("Exporting works in 3 steps:\n")

  setFgColor(unpack(svo.getDefaultColorNums))
  echo("a) select what data about people you'd like to export:\n")
  for key, _ in pairs(ndb.schema.people) do
    echo("  ")

    if key == "name" then
      echoLink("[X] name", [[svo.echof("The name has to stay, otherwise what'll be there to import?")]], "If you'd just like to share the list of names known, you can tick everything else off and leave this on", true)
    else
      echoLink("["..(ndb.exportdata.fields[key] and 'X' or ' ')..'] '..key, 
        [[ndb.exportdata.fields.]]..key..[[ = ]]..tostring(not ndb.exportdata.fields[key])..[[;ndb.exportmenu()]],
        'Click to '..(not ndb.exportdata.fields[key] and 'add' or 'remove') .. ' '..key .. ' for export', true)
    end
    echo("\n")
  end

  echo("\n")
  echo("b) select which people you'd like to export:\n")
  for key, _ in pairs(ndb.exportdata.people) do
    setFgColor(unpack(svo.getDefaultColorNums))
    echo("  ")

    echoLink("["..(ndb.exportdata.people[key] and 'X' or ' ')..'] '..key, 
      [[ndb.exportdata.people.]]..key..[[ = ]]..tostring(not ndb.exportdata.people[key])..[[;ndb.exportmenu()]],
      (ndb.exportdata.people[key] and 'Click to export '..key or 'Click not to export '..key), true)

    echo("\n")
  end

  echo("\n")
  echo("d) select a folder to export to: ")
  setUnderline(true)
  echoLink((not ndb.exportdata.location and "<folder>" or ndb.exportdata.location), [[
    ndb.exportdata.location = invokeFileDialog(false, "Where do you want to save the file? Select it and click Open")
    if ndb.exportdata.location == "" then ndb.exportdata.location = false end
    ndb.exportmenu()]],
    '', true)
  setUnderline(false)
  echo("\n")

  echo("\n")
  svo.echofn("All set? ")

  setUnderline(true)
  setFgColor(unpack(svo.getDefaultColorNums))
  echoLink("Export!", (not ndb.exportdata.location and 'svo.echof("Pick a folder to export to, silly.")' or 'ndb.doexport()'), 'Click to export', true)
  setUnderline(false)
end

function ndb.importmenu()
  svo.echof("Import NameDB data:")

  setFgColor(unpack(svo.getDefaultColorNums))
  echo("\n")
  if not ndb.importdata.location then echo("a) select a file to import: ") else echo("a) file to import: ") end
  setUnderline(true)
  echoLink((not ndb.importdata.location and "<file>" or ndb.importdata.location), [[
    ndb.importdata.location = invokeFileDialog(true, "Pick the file you'd like to import and select Open")
    if ndb.importdata.location == "" then ndb.importdata.location = false end
    if ndb.importdata.location then ndb.getimportfields() end
    ndb.importmenu()]],
    '', true)
  setUnderline(false)
  echo("\n")

  echo("\n")
  if not ndb.importdata.data then
    echo("b) select which fields to import once you've picked a file")
  else
    echo("b) select which fields to import:\n")
    for key, _ in pairs(ndb.importdata.fields) do
      echo("  ")

      if key == "name" then
        echoLink("[X] name", [[svo.echof("The name has to stay, otherwise how will the import data make sense?")]], "The persons name - this has to stay", true)
      else
        echoLink("["..(ndb.importdata.fields[key] and 'X' or ' ')..'] '..key, 
          [[ndb.importdata.fields.]]..key..[[ = ]]..tostring(not ndb.importdata.fields[key])..[[;ndb.importmenu()]],
          'Click to '..(not ndb.importdata.fields[key] and 'add' or 'remove') .. ' '..key .. ' for import', true)
      end
      echo("\n")
    end
  end
  echo("\n")

  echo("\n")
  svo.echofn("All set? ")

  setUnderline(true)
  setFgColor(unpack(svo.getDefaultColorNums))
  echoLink("Import!", (not ndb.importdata.data and 'svo.echof("Pick a file to import first!")' or 'ndb.doimport()'), 'Click to import', true)
  setUnderline(false)
  echo("\n")
end

function ndb.checkqw(suffix, how)
  ndb.qwtype = how or "names"
  ndb.lookup_online(how == "update")
end

function ndb.show_online()
  local names = ndb.last_online or {}
  local how = ndb.qwtype
  ndb.qwtype = nil
  if not how then return end
  if how == "organize cities" then
    local cities = {}
    for _, name in ipairs(names) do
      local city = ndb.getcity(name)
      if not city or city == "" then city = "unknown" end
      cities[city] = cities[city] or {}
      cities[city][#cities[city] + 1] = name
    end
    local sorted = {}
    for city, members in pairs(cities) do sorted[#sorted + 1] = {city = city, members = members} end
    table.sort(sorted, function(a, b)
      if #a.members == #b.members then return a.city < b.city end
      return #a.members > #b.members
    end)
    svo.echof("Online names by cached API city (unknown is not rogue):")
    for _, group in ipairs(sorted) do
      table.sort(group.members)
      echo(("  %s (%d): %s\n"):format(group.city, #group.members, table.concat(group.members, ", ")))
    end
  elseif how:match("^report members of ") then
    local org = how:match("^report members of (%w+)"):lower()
    local members = {}
    for _, city in ipairs(ndb.valid.cities) do
      if city:lower():sub(1, #org) == org then
        org = city
        for _, name in ipairs(names) do
          if ndb.getcity(name) == city then members[#members + 1] = name end
        end
        break
      end
    end
    table.sort(members)
    if #members == 0 then svo.echof("No online names have a verified cached city of %s.", org)
    else svo.cc("%s %s visible (cached API city): %s", #members, ndb.getpluralcity(org, #members), table.concat(members, ", ")) end
  else
    table.sort(names)
    svo.echof("Official API online list (%d): %s", #names, table.concat(names, ", "))
  end
end