-- Svof (c) 2011-2018 by Vadim Peretokin

-- Svof is licensed under a
-- Creative Commons Attribution-NonCommercial-ShareAlike 4.0 International License.

-- You should have received a copy of the license along with this
-- work. If not, see <http://creativecommons.org/licenses/by-nc-sa/4.0/>.

-- Needs the core loaded first, for svo.pl and the rest of it. As a separate
-- module that was implied by load order, and a zero-delay timer was enough to
-- get behind it. In a single package this script can run before
-- svo_init_system does, so wait for the system explicitly instead.
local function ndb_load()

local me = svo.me
me.watchfor = me.watchfor or {}
me.highlightignore = me.highlightignore or {}
local firstload = not ndb.ismhaldorian

-- Mudlet continues loading sibling scripts after a script error. If authority
-- migration failed, retain SQLite/personal data but never expose rolled-back
-- legacy identity as authoritative facts through readers or highlights.
local function fetch_people(...)
  local rows = db.fetch(db, ndb.db.people, ...)
  if not ndb.authority_ready then
    for _, person in ipairs(rows) do
      for key, value in pairs(ndb.fact_defaults) do person[key] = value end
    end
  end
  return rows
end

svo.pl.dir.makepath(getMudletHomeDir() .. "/svo/namedb")

-- load the highlightignore list
function ndb.loadhighlightignore()
  local conf_path = getMudletHomeDir() .. "/svo/config/highlightignore"

  if lfs.attributes(conf_path) then
    local t = {}
    local ok, msg = pcall(table.load, conf_path, t)
    if ok then
	    me.highlightignore = me.highlightignore or {} -- make sure it's initialized
	    svo.update(me.highlightignore, t)
	else
		os.remove(conf_path)
		tempTimer(10, function()
		  svo.echof("Your NameDB highlights ignored file got corrupted for some reason - I've deleted it so the system can load other stuff OK. You'll need to re-do all the names to ignore highlighting, though. (%q)", msg)
		end)
	end
  end
end
if firstload then ndb.loadhighlightignore() end
svo.signals.saveconfig:connect(function () me.highlightignore = me.highlightignore or {}; svo.tablesave(getMudletHomeDir() .. "/svo/config/highlightignore", me.highlightignore) end, 'save highlightignore list')

-- save the ndb.conf.citypolitics list
if ndb.conf == nil then ndb.loadsettings() end
svo.signals.saveconfig:connect(function () ndb.conf.citypolitics = ndb.conf.citypolitics or {}; svo.tablesave(getMudletHomeDir() .. "/svo/namedb/citypolitics", ndb.conf.citypolitics) end, 'save citypolitics list')


svo.signals.saveconfig:connect(function ()
	-- this can error out if the connection is closed
  pcall(function() db.__conn['namedb']:execute('VACUUM') end)
end, 'vacuum namedb database')

--ndb.API
function ndb.ismhaldorian(name)
  if not ndb.authority_ready then return false end
  return #(fetch_people({db:eq(ndb.db.people.city, 'Mhaldor'), db:eq(ndb.db.people.name, name)})) ~= 0
end

function ndb.iscyrenian(name)
  if not ndb.authority_ready then return false end
  return #(fetch_people({db:eq(ndb.db.people.city, 'Cyrene'), db:eq(ndb.db.people.name, name)})) ~= 0
end

function ndb.isshallamese(name)
  if not ndb.authority_ready then return false end
  return #(fetch_people({db:OR(db:eq(ndb.db.people.city, 'Shallam'), db:eq(ndb.db.people.city, 'Targossas')), db:eq(ndb.db.people.name, name)})) ~= 0
end

function ndb.istargossian(name)
  if not ndb.authority_ready then return false end
  return #(fetch_people({db:eq(ndb.db.people.city, 'Targossas'), db:eq(ndb.db.people.name, name)})) ~= 0
end

function ndb.iseleusian(name)
  if not ndb.authority_ready then return false end
  return #(fetch_people({db:eq(ndb.db.people.city, 'Eleusis'), db:eq(ndb.db.people.name, name)})) ~= 0
end

function ndb.isashtani(name)
  if not ndb.authority_ready then return false end
  return #(fetch_people({db:eq(ndb.db.people.city, 'Ashtan'), db:eq(ndb.db.people.name, name)})) ~= 0
end

function ndb.ishashani(name)
  if not ndb.authority_ready then return false end
  return #(fetch_people({db:eq(ndb.db.people.city, 'Hashan'), db:eq(ndb.db.people.name, name)})) ~= 0
end

function ndb.isundead(name)
  if not ndb.authority_ready then return false end
  return #(fetch_people({db:eq(ndb.db.people.city, 'Undead'), db:eq(ndb.db.people.name, name)})) ~= 0
end
				
function ndb.isclass(name, class)
  if not ndb.authority_ready then return false end
  name, class = name:title(), class:lower()
  return #(fetch_people({db:eq(ndb.db.people.class, class), db:eq(ndb.db.people.name, name)})) ~= 0
end

function ndb.getclass(name)
  name = name:title()
  local r = fetch_people(db:eq(ndb.db.people.name, name))
  if not next(r) then return nil, "name not known" end

  return r[1].class:lower()
end


function ndb.getcity(name)
  name = name:title()
  local r = fetch_people(db:eq(ndb.db.people.name, name))
  if not next(r) then return nil, "name not known" end

  return r[1].city
end

function ndb.getnotes(name)
  name = name:title()
  local r = fetch_people(db:eq(ndb.db.people.name, name))
  if not next(r) then return nil, "name not known" end

  return r[1].notes
end

function ndb.getxprank(name)
  name = name:title()
  local r = fetch_people(db:eq(ndb.db.people.name, name))
  if not next(r) then return nil, "name not known" end

  return r[1].xp_rank
end

function ndb.ismark(name)
  name = name:title()
  local r = fetch_people(db:eq(ndb.db.people.name, name))
  if not next(r) then return nil, "name not known" end

  if r[1].mark == "" then return nil, "unknown"
  else return r[1].mark end
end


function ndb.isinfamous(name)
  name = name:title()
  local r = fetch_people(db:eq(ndb.db.people.name, name))
  if not next(r) then return nil, "name not known" end

  if r[1].infamous == "" then return -1
  else return r[1].infamous end
end


function ndb.isdragon(name)
  svo.assert(name, "ndb.isdragon() requires a name")

  name = name:title()
  local r = fetch_people(db:eq(ndb.db.people.name, name))
  if not next(r) then return nil, "name not known" end

  if r[1].dragon == -1 then return nil, "unknown" end
  return (r[1].dragon == 1 and true or false)
end

function ndb.getcityrank(name)
  svo.assert(name, "ndb.getcityrank() requires a name")

  name = name:title()
  local r = fetch_people(db:eq(ndb.db.people.name, name))
  if not next(r) then return nil, "name not known" end

  return ndb.valid.cityranks[r[1].city] and ndb.valid.cityranks[r[1].city][r[1].city_rank] or nil
end


function ndb.isimmortal(name)
  name = name:title()
  local r = fetch_people(db:eq(ndb.db.people.name, name))
  if not next(r) then return nil, "name not known" end
  if r[1].immortal == -1 then return nil, "unknown" end

  return (r[1].immortal == 1 and true or false)
end

function ndb.exists(name)
  return #(fetch_people(db:eq(ndb.db.people.name, name))) ~= 0
end

function ndb.isperson(name)
  return #(fetch_people(db:eq(ndb.db.people.name, name))) ~= 0
end

-- returns true only if a certain enemy
function ndb.isenemy(name)
  local p = ndb.getname(name)
  if not p then return false end

  local city = p.city

  -- -1 autodetected, 1 enemy, 2 ally
  if p.iff == 1 or
       (p.iff ~= 2 and
         ((city and city ~= "" and ndb.conf.citypolitics[city] == 'enemy') or
         (p.cityenemy == 1 or p.orderenemy == 1 or p.houseenemy == 1))) then
    return true else return false
  end
end

-- returns true if they are a soldier of their city
function ndb.issoldier(name)
  local p = ndb.getname(name)
  if not p or p.city_soldier == -1 then return nil, "unknown" end

 -- only return true for soldier of their city
  if p.city_soldier == -2 then
    return true else return false
  end
end

-- returns true only if someone is a city enemy. They could be a house enemy, order enemy, or politics enemy and not be considered an enemy by this
function ndb.isonlycityenemy(name)
  local p = ndb.getname(name)
  if not p then return false end

  local city = p.city

 -- only return true for city enemy
  if p.cityenemy == 1 then
    return true else return false
  end
end

-- returns true only if someone is an enemy via iff or is a city enemy. They could be a house enemy, and not be considered an enemy by this
function ndb.iscityenemy(name)
  local p = ndb.getname(name)
  if not p then return false end

  local city = p.city

  -- -1 autodetected, 1 enemy, 2 ally
  if p.iff == 1 or
       (p.iff ~= 2 and
         ((city and city ~= "" and ndb.conf.citypolitics[city] == 'enemy') or
         (p.cityenemy == 1))) then
    return true else return false
  end
end

-- given a title, returns all info about a person
function ndb.getnamebytitle (title)
  return fetch_people(db:in_(ndb.db.people.name, string.split(title, " ")))
end

-- given a line, returns the first name it finds, if any
function ndb.findname(line)
  for w in string.gmatch(line, "(%u%l+)") do
    if #w >= 3 then
      if ndb.isperson(w) then return w end
    end
  end
end

-- given a line, returns all names found on it
function ndb.findnames(line)
  local l = {}
  for w in string.gmatch(line, "(%u%l+)") do
    if #w >= 3 then
      if ndb.isperson(w) then l[#l+1] = w end
    end
  end

  if l[1] then return l end
end

-- given a name, returns all info about a person
function ndb.getname (name)
  return fetch_people(db:eq(ndb.db.people.name, string.title(name)))[1]
end

local singular_city = {
  [""] = 'Rogue',
  Mhaldor = 'Mhaldorian',
  Ashtan = 'Ashtani',
  Hashan = 'Hashani',
  Eleusis = 'Eleusian',
  Shallam = 'Shallamese',
  Targossas = 'Targossian',
  Cyrene = 'Cyrenian',
  Undead = 'Undead'
}

local plural_city = {
  [""] = 'Rogues',
  Mhaldor = 'Mhaldorians',
  Ashtan = 'Ashtani',
  Hashan = 'Hashani',
  Eleusis = 'Eleusians',
  Shallam = 'Shallamese',
  Targossas = 'Targossians',
  Cyrene = 'Cyrenians',
  Undead = 'Undead'
}

local plural_class = {
  Apostate    = 'Apostates',
  Bard        = 'Bards',
  Blademaster = 'Blademasters',
  Dragon      = 'Dragons',
  Druid       = 'Druids',
  Infernal    = 'Infernals',
  Jester      = 'Jesters',
  Magi        = 'Magi',
  Monk        = 'Monks',
  Occultist   = 'Occultists',
  Paladin     = 'Paladins',
  Priest      = 'Priests',
  Runewarden  = 'Runewardens',
  Sentinel    = 'Sentinels',
  Serpent     = 'Serpents',
  Shaman      = 'Shamans',
  Sylvan      = 'Sylvans',
  Undead      = 'Undead'
}

function ndb.getpluralclass(class, count)
  if count <= 1 then
    return class
  else
    return plural_class[class]
  end
end

function ndb.getpluralcity(city, count)
  if count <= 1 then
    return singular_city[city]
  else
    return plural_city[city]
  end
end

local function getcolor(name)
  local person = ndb.getname(name)

  if not person then return "" end -- in case the person doesn't exist

  local city, order, conf, color = person.city, person.order, svo.conf

  -- order of priority: watchfor > divine > city > order > house > citizens.
  city = city:lower()

  -- color first
  if conf.highlightwatchfor and svo.me.watchfor[name] then
    color     = conf.watchforcolor or 'a_darkwhite'

  elseif conf.highlightdivine and person.immortal == 1 then
    color     = conf.divinecolor or 'a_darkwhite'

  elseif conf.highlightcity and person.cityenemy == 1 then
    color     = conf.citycolor or 'a_darkwhite'

  elseif conf.highlightorder and person.orderenemy == 1 then
    color     = conf.ordercolor or 'a_darkwhite'

  elseif conf.highlighthouse and person.houseenemy == 1 then
    color     = conf.housecolor or 'a_darkwhite'

  elseif order and conf['highlight'..order] then
    color     = conf[order..'color'] or 'a_darkwhite'

  elseif city == "rogue" and conf.highlightrogues then
    color     = conf.roguescolor or 'a_darkwhite'

  elseif city ~= "" and conf['highlight'..city] then
    color     = conf[city..'color'] or 'a_darkwhite'
  end

  return color
end

function ndb.getcolor(name)
  svo.assert(type(name) == 'string', "ndb.getcolor: name to get a color of is required")

  local color = getcolor(name)

  return ((color and color ~= "") and '<'..color..'>' or "")
end

function ndb.getcolorn(name)
  svo.assert(type(name) == 'string', "ndb.getcolorn: name to get a color of is required")

  local color = getcolor(name)

  return ((color and color ~= "") and ('<'..color..'>'..name..'<reset>') or name)
end

function ndb.getcolorp(name)
  svo.assert(type(name) == 'string', "ndb.getcolorp: name to get a color of is required")

  local color = getcolor(name)

  return color
end

for _, format in ipairs{'bold', 'underline', 'italicize'} do
  ndb['should'..format] = function(name)
    svo.assert(type(name) == 'string', "ndb.should"..format..": name to get a color of is required")

    local person = ndb.getname(name)

    if not person then return false end -- in case the person doesn't exist

    local city, order, conf = person.city, person.order, svo.conf

    return (conf[format..'watchfor'] and svo.me.watchfor[name])    or
           (conf[format..'city'] and person.cityenemy == 1)        or
           (conf[format..'order'] and person.orderenemy == 1)      or
           (conf[format..'house'] and person.houseenemy == 1)      or
           (conf[format..'divine'] and person.immortal == 1)       or
           (order and conf[format..order])                         or
           ((city == 'rogue') and conf[format..'rogues']) or
           (city and conf[format..city])                           or false
  end
end

function ndb.addname(name)
  local rows = {}
  if type(name) == "table" then
    for _, value in ipairs(name) do rows[#rows + 1] = {name = value} end
  else
    rows[1] = {name = name}
  end
  ndb.merge_discovery(rows)
  raiseEvent("NameDB got new data")
end

function ndb.setiff(name, status)
  name = name:lower():title()

  local category = 'iff'
  local towhat

  -- -1 autodetected, 1 enemy, 2 ally
  status = status:lower()
  if status == 'enemy' then
    towhat = 1
  elseif status == 'ally' then
    towhat = 2
  else
    towhat = -1
  end

  local temp_name_list = {{
    name = name,
    [category] = towhat
  }}

  ndb.merge_discovery(temp_name_list)
end

-- ndb.support

function ndb.tablemerge(t, other)
   for other_key, other_items in pairs(other) do
      if not t[other_key] then
         t[other_key] = other_items
      else
         local group = t[other_key]
         for item_key, item_value in pairs(other_items) do
            group[item_key] = item_value
         end
      end
   end
   return t
end

-- given a string and a table of possible answers, returns the first possible answer, if any
function ndb.findfromtable(input, valid)
  local sfind = string.find

  for i = 1, #valid do
    if sfind(input, valid[i], 1, true) then return valid[i] end
  end
end


function ndb.showhelp(entry)
  svo.echof("<0,250,0>"..ndb.help[entry].term.."<47,79,79>: "..svo.getDefaultColor()..table.concat(ndb.help[entry].definition, "\n"))
  svo.showprompt() echo'\n'
end


function ndb.getrankincity(city, name)
  city, name = city:title(), name:title()
  if ndb.valid.cityranks[city] then return ndb.valid.cityranks[city][name] end
end


function ndb.doexport()
  if not ndb.exportdata.location then return nil, "no export location" end

  local alldata = fetch_people()

  if not alldata or not next(alldata) then svo.echof("Your NameDB is empty! Check 'qw', 'citizens' to start filling it up. There's nothing to export otherwise...") return end

  for i = 1, #alldata do
    local p = alldata[i]

    -- see if we need to prune the result first
    if not ndb.exportdata.people.all then
      alldata[i] = nil

    else
      -- prune fields we don't need
      for key,value in pairs(ndb.exportdata.fields) do
        if key ~= 'name' and not value then p[key] = nil end
      end

      -- prune internal fields starting with underscores
      local removekeys = {}
      for key, _ in pairs(p) do
        if key:sub(1,1) == '_' then
          removekeys[#removekeys+1] = key
        end
      end
      if not next(removekeys) == nil then
        for _ = 1, #removekeys do p[removekeys[i]] = nil end
      end
    end
  end

  -- build the final table that we'll svo.tablesave()
  local exportable = {
    meta = { author = gmcp.Char.Status.name, date = os.date("%A %d, %b '%y"), fields =  ndb.exportdata.fields },
    data = alldata
  }

  local location = string.format("%s/%s's namedb, %s", ndb.exportdata.location, gmcp.Char.Status.name,os.date("%A %d, %b '%y"))
  svo.tablesave(location, exportable)
  echo'\n' svo.echof("Data exported okay, it's in %s.", location)
end

-- reads selected files for fields available within it to import
function ndb.getimportfields()

  if not ndb.importdata.location or not io.exists(ndb.importdata.location) then ndb.importdata.location = nil; return end

  ndb.importdata.data = {}
  table.load(ndb.importdata.location, ndb.importdata.data)
  if not ndb.importdata.data then svo.echof("Couldn't read the file - maybe it's corrupted? Try another.") return end

  for k in pairs(ndb.importdata.data.meta.fields) do
    if k == "name" or ndb.policy_fields[k] then ndb.importdata.fields[k] = true end
  end
end

function ndb.doimport()
  if not ndb.importdata.data then return nil, "no data loaded in ndb.importdata.data" end

  -- copy data over for importing with only the fields we need
  local temp_name_list = {}

  -- data.data as the original data is stored in .data of the new field that's imported.
  for i = 1, #ndb.importdata.data.data do
    local p = ndb.importdata.data.data[i]

    temp_name_list[#temp_name_list + 1] = {
      name = p.name,
    }

    for k,v in pairs(p) do
      if ndb.importdata.fields[k] and ndb.policy_fields[k] then
        temp_name_list[#temp_name_list][k] = v
      end
    end
  end

  ndb.merge_discovery(temp_name_list)
  svo.echof("Imported %d name%s okay.", #temp_name_list, (#temp_name_list == 1 and '' or 's'))

  raiseEvent("NameDB got new data")
  ndb.importdata.data = nil
end

function ndb.loadhighlights()
  ndb.highlightIDs = ndb.highlightIDs or {}
  collectgarbage('stop')

  ndb.cleartriggers()

  if svo.conf.ndbpaused then return end

  local highlight, watchfor = ndb.singlehighlight, svo.me.watchfor

  local dbnames = fetch_people()

  for i = 1, #dbnames do
    highlight(dbnames[i].name,
      dbnames[i].city or "",
      dbnames[i].order or "",
      dbnames[i].cityenemy or 0,
      dbnames[i].orderenemy or 0,
      dbnames[i].houseenemy or 0,
      watchfor[dbnames[i].name],
      dbnames[i].immortal or 0
    )
  end

  collectgarbage()
end

function ndb.singlehighlight(name, city, order, cityenemy, orderenemy, houseenemy, watchfor, immortal)
  if ndb.highlightIDs and ndb.highlightIDs[name] then
    killTrigger(ndb.highlightIDs[name])
    ndb.highlightIDs[name] = nil
  end

  if name == svo.me.name or svo.me.highlightignore[name] or svo.conf.ndbpaused then return end

  local color, bold, underline, italicize
  local conf = svo.conf

  -- order of priority: watchfor > divine > city > order > house > citizens.

  city = city:lower()
  if order == "" then order = false else order = order:lower() end

  -- color first
  if conf.highlightwatchfor and watchfor then
    color     = conf.watchforcolor or 'a_darkwhite'

  elseif conf.highlightdivine and immortal == 1 then
    color     = conf.divinecolor or 'a_darkwhite'

  elseif conf.highlightcity and cityenemy == 1 then
    color     = conf.citycolor or 'a_darkwhite'

  elseif conf.highlightorder and orderenemy == 1 then
    color     = conf.ordercolor or 'a_darkwhite'

  elseif conf.highlighthouse and houseenemy == 1 then
    color     = conf.housecolor or 'a_darkwhite'

  elseif order and conf['highlight'..order] then
    color     = conf[order..'color'] or 'a_darkwhite'

  elseif (city == 'rogue') and conf.highlightrogues then
    color     = conf.roguescolor or 'a_darkwhite'

  elseif city and conf['highlight'..city] then
    color     = conf[city..'color'] or 'a_darkwhite'
  end

  -- rest of things
  bold      = (conf.boldwatchfor and watchfor)            or
                (conf.boldcity and cityenemy == 1)        or
                (conf.boldorder and orderenemy == 1)      or
                (conf.boldhouse and houseenemy == 1)      or
                (conf.bolddivine and immortal == 1)       or
                (order and conf['bold'..order])           or
                ((city == 'rogue') and conf.boldrogues) or
                (city and conf['bold'..city])

  underline = (conf.underlinewatchfor and watchfor)       or
                (conf.underlinecity and cityenemy == 1)   or
                (conf.underlineorder and orderenemy == 1) or
                (conf.underlinehouse and houseenemy == 1) or
                (conf.underlinedivine and immortal == 1)  or
                (order and conf['underline'..order])      or
                ((city == 'rogue') and conf.underlinerogues) or
                (city and conf['underline'..city])

  italicize = (conf.italicizewatchfor and watchfor)       or
                (conf.italicizecity and cityenemy == 1)   or
                (conf.italicizeorder and orderenemy == 1) or
                (conf.italicizehouse and houseenemy == 1) or
                (conf.italicizedivine and immortal == 1)  or
                (order and conf['italicize'..order])      or
                ((city == 'rogue') and conf.italicizerogues) or
                (city and conf['italicize'..city])

  if not (color or bold or underline or italicize) then return end

  ndb.highlightIDs = ndb.highlightIDs or {}
  ndb.highlightIDs[name] = tempTrigger(name, ([[ndb.highlight("%s", %s, %s, %s, %s)]]):format(name,
    (color     and '"'..color..'"' or 'false'),
    (bold      and 'true' or 'false'),
    (underline and 'true' or 'false'),
    (italicize and 'true' or 'false')
  ))
end

function ndb.cleartriggers()
  if not ndb.highlightIDs or not next(ndb.highlightIDs) then return end

  local killTrigger = killTrigger
  for _,v in pairs(ndb.highlightIDs) do
    killTrigger(v)
  end

  ndb.highlightIDs = {}
end

function ndb.highlight(who, color, bold, underline, italicize)
  -- c counts the appearance of the substring of the word in the line, k counts the character position
  local c, k = 1, 1
  while k > 0 do
    k = line:find(who, k)
    if k == nil then return; end
    c = c + 1

    if k == line:find("%f[%a]"..who.."%f[%A]", k) then
      if selectString(who, c-1) > -1 then
        if color     then fg(color) end
        if bold      then setBold(true) end
        if underline then setUnderline(true) end
        if italicize then setItalics(true) end
        resetFormat()
      else return end
    end

--    k = k + #who
    k = k + 1 -- this is a quicker optimization
  end
end


ndb.configs()
ndb.loadhighlights()
if ndb.pending_facts_reset then
  ndb.pending_facts_reset = nil
  raiseEvent("NameDB facts reset")
end

end

if ndb.load_handler then
  killAnonymousEventHandler(ndb.load_handler)
  ndb.load_handler = nil
end
if svo and svo.systemloaded then
  ndb_load()
else
  ndb.load_handler = registerAnonymousEventHandler("svo system loaded", function()
    ndb.load_handler = nil
    ndb_load()
  end, true)
end
