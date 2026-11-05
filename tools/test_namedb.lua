-- From Sources/svof: lua tools/test_namedb.lua
-- Actual native group scripts + Mudlet 4.19.1 DB.lua + LuaSQL SQLite + YAJL.
local Native = dofile("tools/namedb_fixture.lua")
local checks = 0
local function eq(actual, expected, label)
  checks = checks + 1
  assert(actual == expected, (label or "value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function count(events, name)
  local n = 0; for _, event in ipairs(events) do if event.name == name then n = n + 1 end end; return n
end
local fixtures = {}
local function fixture(options)
  local f = Native.install(nil, options)
  fixtures[#fixtures + 1] = f
  return f
end
local function scalar(c, sql, key)
  local cur = assert(c:execute(sql)); local row = cur:fetch({}, "a"); cur:close()
  return row and row[key]
end
local function tests()
  local f = fixture({defer = true})
  local e = f.env
  e.svo.conf.autocheck = false
  e.db:create("NameDB", {})
  local c = e.db.__conn.namedb
  assert(c:execute([[CREATE TABLE people (_row_id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT UNIQUE, class TEXT DEFAULT '', city TEXT DEFAULT '', notes TEXT DEFAULT '',
    iff REAL DEFAULT -1, importance REAL DEFAULT 0, cityenemy REAL DEFAULT 0,
    houseenemy REAL DEFAULT 0, orderenemy REAL DEFAULT 0, race TEXT DEFAULT '',
    immortal REAL DEFAULT 0, custom TEXT DEFAULT '', _private TEXT DEFAULT '')]]))
  assert(c:execute([[CREATE INDEX custom_city_index ON people(city)]]))
  assert(c:execute([[CREATE TABLE private_settings (value TEXT)]]))
  assert(c:execute([[INSERT INTO private_settings VALUES('keep')]]))
  assert(c:execute([[INSERT INTO people(name,class,city,notes,iff,importance,cityenemy,houseenemy,orderenemy,race,custom,_private)
    VALUES('Bob','monk','Mhaldor','personal note',2,7,1,1,1,'dragon','custom data','private data')]]))
  assert(c:commit())
  local custom_database = e.db:create("NameDB", {private_settings = {value = ""}})
  e.ndb = {conf = {citypolitics = {Mhaldor = "enemy"}}}
  e.svo.me.watchfor.Bob, e.svo.me.highlightignore.Ignored = true, true
  e.svo.conf.highlightwatchfor, e.svo.conf.watchforcolor = true, "a_red"
  e.svo.conf.highlightrogues, e.svo.conf.roguescolor = true, "a_green"
  local sends = #f.world.sent
  f.reload()
  eq(count(f.events, "NameDB facts reset"), 1, "one-time migration event")
  local n = e.ndb
  eq(n.getclass("Bob"), "", "legacy class reset")
  eq(n.getcity("Bob"), "", "legacy city reset")
  eq(n.getnotes("Bob"), "personal note", "notes preserved")
  local bob = n.getname("Bob")
  eq(bob.race, "", "unsupported old fact reset")
  eq(bob.iff, 2); eq(bob.importance, 7); eq(bob.cityenemy, 1); eq(bob.houseenemy, 1); eq(bob.orderenemy, 1)
  eq(bob.custom, "custom data"); eq(bob._private, "private data")
  eq(n.isenemy("Bob"), false, "personal ally overrides all enemies")
  eq(n.conf.citypolitics.Mhaldor, "enemy")
  eq(e.svo.me.watchfor.Bob, true); eq(e.svo.me.highlightignore.Ignored, true)
  eq(n.getcolor("Bob"), "<a_red>", "real policy color getter")
  eq(type(n.highlightIDs.Bob), "number", "real highlighter installed")
  local highlighted = n.highlightIDs.Bob
  e.svo.me.highlightignore.Bob = true
  e.raiseEvent("NameDB highlightignore name changed", "Bob")
  eq(n.highlightIDs.Bob, nil, "native ignore update releases highlight ownership")
  eq(f.world.triggers[highlighted].killed, true)
  e.svo.me.highlightignore.Bob = nil
  e.raiseEvent("NameDB highlightignore name changed", "Bob")
  eq(type(n.highlightIDs.Bob), "number")
  eq(scalar(c, "SELECT value FROM private_settings", "value"), "keep", "custom table")
  eq(e.db:fetch(custom_database.private_settings)[1].value, "keep", "native custom sheet reference survives cutover")
  eq(e.db:fetch(n.db.private_settings)[1].value, "keep", "native custom sheet registration preserved")
  eq(scalar(c, "SELECT name FROM sqlite_master WHERE name='custom_city_index'", "name"), "custom_city_index", "custom index")
  eq(tonumber(scalar(c, "SELECT version FROM namedb_authority", "version")), 1)
  eq(#f.world.sent, sends, "migration sends no commands")
  n.addname("Unknownperson")
  eq(n.getclass("Unknownperson"), "")
  eq(n.getname("Unknownperson").immortal, -1, "old SQL defaults cannot imply known facts")
  eq(n.isimmortal("Unknownperson"), nil)
  eq(n.isdragon("Unknownperson"), nil)
  eq(n.ismark("Unknownperson"), nil)
  eq(n.isinfamous("Unknownperson"), -1, "native unknown infamy sentinel retained")
  eq(n.issoldier("Unknownperson"), nil)
  eq(n.getcityrank("Unknownperson"), nil)
  eq(n.getcolor("Unknownperson"), "", "unknown city is not rogue")
  n.addname("Ignored")
  e.svo.me.watchfor.Ignored = true
  n.addhighlightname(nil, "Ignored")
  eq(n.highlightIDs.Ignored, nil, "native highlightignore overrides watchfor")
  n.cancel_lookups()
  local before = #f.downloads
  for _, name in ipairs({"Bob/../x", "Bob?x", "Bob\nSEND", "x", "A1ice", string.rep("a", 31)}) do
    eq(n.lookup(name), nil, "name validation")
  end
  eq(#f.downloads, before)
  assert(n.lookup("bOB")); assert(n.lookup("Bob"))
  eq(#f.downloads, before + 1, "canonical dedup")
  eq(f.downloads[#f.downloads].url, "https://api.achaea.com/characters/bob.json")
  -- JSON escapes are intentionally parsed by real YAJL, never a test decoder.
  local verified = [[{"name":"Bob","fullname":"Bob, the \"quoted\"","class":"Runewarden","city":"ashtan","house":"vanguard","level":"101","xp_rank":"42","mob_kills":"1.2k","player_kills":"12","explorer_rank":"19","notes":"not ours","iff":1}]]
  f.deliver(#f.downloads, verified)
  eq(n.getclass("Bob"), "runewarden"); eq(n.getcity("Bob"), "Ashtan")
  eq(n.getname("Bob").title, 'Bob, the "quoted"')
  eq(n.getname("Bob").mob_kills, "1.2k"); eq(n.getname("Bob").player_kills, 12); eq(n.getname("Bob").explorer_rank, 19)
  eq(n.getnotes("Bob"), "personal note"); eq(n.getname("Bob").iff, 2)
  eq(n.getname("Bob").dragon, -1, "level does not invent unsupported dragon fact")
  eq(count(f.events, "NameDB character updated"), 1)
  eq(f.events[#f.events].args[1], "Bob", "canonical postcommit event")
  -- A consumer can read committed facts during event delivery.
  local native_raise, observed = e.raiseEvent, nil
  e.raiseEvent = function(event, name, ...)
    if event == "NameDB character updated" then observed = n.getclass(name) end
    return native_raise(event, name, ...)
  end
  assert(n.lookup("Bob"))
  assert(c:execute([[UPDATE people SET class='monk',city='Mhaldor' WHERE name='Bob']]))
  assert(c:commit())
  f.alias("(ndb set person category value) Adjust person data", {"", "Bob", "notes", "in-flight annotation"})
  n.setiff("Bob", "enemy")
  f.deliver(#f.downloads, verified)
  eq(observed, "runewarden", "event after commit and overwrite in-flight factual edits")
  eq(n.getnotes("Bob"), "in-flight annotation", "in-flight annotation survives API response")
  eq(n.getname("Bob").iff, 1, "in-flight personal policy survives API response")
  e.raiseEvent = native_raise
  local event_count = count(f.events, "NameDB character updated")
  -- Every non-API writer keeps discovery/policy but cannot change facts.
  n.merge_discovery({{name = "Bob", class = "magi", city = "Cyrene", notes = "kept annotation"}})
  eq(n.getclass("Bob"), "runewarden"); eq(n.getnotes("Bob"), "kept annotation")
  f.alias("(ndb set person category value) Adjust person data", {"", "Bob", "class", "magi"})
  eq(n.getclass("Bob"), "runewarden")
  eq(pcall(n.fixed_set, n.db.people.class, "magi"), false)
  e.temp_name_list = {{name = "Bob", class = "monk", city = "Hashan"}}
  f.trigger("Data Capture/Lists/Stop_getting_(hwho).lua")
  eq(n.getclass("Bob"), "runewarden"); eq(n.getcity("Bob"), "Ashtan")
  for _, field in ipairs({"city", "house", "order"}) do
    local sent_before = #f.world.sent
    e.svo.conf["highlight" .. field] = true
    e.svo.conf[field .. "color"] = "a_red"
    f.alias("Enemies lists", {"", field, " add"})
    eq(f.world.sent[sent_before + 1], field .. " enemies", "explicit policy list command preserved")
    e.multimatches = {{}, {}, {}, {"Listnew, Bob"}}
    f.trigger("Data Capture/Lists/City-House-Order_enemies.lua")
    eq(n.getname("Listnew")[field .. "enemy"], 1, "enemy add enriches newly discovered name")
    eq(n.getname("Bob")[field .. "enemy"], 1)
    eq(n.getclass("Bob"), "runewarden", "enemy lists cannot overwrite identity")
  end
  local wildcard = e.getColorWildcard
  e.getColorWildcard = function() return {"Bob"} end
  e.line = "Bob"
  for _, capture in ipairs({
    {"NameDB_cwho.lua", "Get_name_(cwho).lua", "Stop_getting_(cwho).lua"},
    {"Clan_who.lua", "Get_name_(clan_who).lua", "Stop_(clan_who).lua"},
    {"Friend_Checking.lua", "Get_name_(Friend).lua", "Stop_(friend_who).lua"},
    {"Party_who.lua", "Get_name_(party_who).lua", "Stop_(party_who).lua"},
  }) do
    f.trigger("Data Capture/Lists/" .. capture[1])
    f.trigger("Data Capture/Lists/" .. capture[2])
    eq(e.temp_name_list[1].name, "Bob")
    eq(e.temp_name_list[1].class, nil, "game lists discover names, not identity facts")
    eq(n.temp_classes_list.runewarden, 1, "annotations read the real authoritative class getter")
    f.trigger("Data Capture/Lists/" .. capture[3])
    eq(n.getclass("Bob"), "runewarden")
  end
  e.getColorWildcard = wildcard
  n.importdata = {fields = {class = true, city = true, notes = true, iff = true},
    data = {data = {{name = "Bob", class = "magi", city = "Cyrene", notes = "roundtrip", iff = 1}}}}
  n.doimport()
  eq(n.getclass("Bob"), "runewarden"); eq(n.getcity("Bob"), "Ashtan")
  eq(n.getnotes("Bob"), "roundtrip"); eq(n.isenemy("Bob"), true)
  local report_before = #f.world.sent
  local paused = e.svo.conf.paused
  e.svo.conf.paused = false
  f.alias("(ppof) Report visible citizens of a city", {"", "Ashtan"})
  f.deliver(#f.downloads, [[{"count":1,"characters":[{"name":"Bob"}]}]])
  e.svo.conf.paused = paused
  eq(#f.world.sent, report_before + 1, "explicit ppof reporting preserved")
  -- Export/import policy roundtrip goes through the native UI actions and real SQLite.
  local saved
  local save = e.svo.tablesave
  e.svo.tablesave = function(_, value) saved = value end
  e.gmcp.Char.Status.name = "Tester"
  n.exportdata = {location = f.profile, fields = {name = true, notes = true, iff = true}, people = {all = true}}
  n.doexport()
  assert(saved and saved.data)
  e.svo.tablesave = save
  n.merge_discovery({{name = "Bob", notes = "changed", iff = 2}})
  n.importdata = {fields = {notes = true, iff = true}, data = saved}; n.doimport()
  eq(n.getnotes("Bob"), "roundtrip"); eq(n.getname("Bob").iff, 1)
  eq(n.getname("Bob").custom, "custom data")
  -- Valid privacy omissions replace old verified values with unknown.
  assert(n.lookup("Bob")); f.deliver(#f.downloads, [[{"name":"Bob","city":"(hidden)","house":"(hidden)","class":null}]])
  eq(n.getcity("Bob"), ""); eq(n.getclass("Bob"), ""); eq(n.getname("Bob").guild, "")
  eq(n.getname("Bob").level, -1); eq(n.getnotes("Bob"), "roundtrip")
  assert(n.lookup("Bob")); f.deliver(#f.downloads, verified)
  event_count = count(f.events, "NameDB character updated")
  for _, body in ipairs({
    "not json", "I do not recognize that player.", "[]",
    [[{"name":"Alice","class":"magi"}]], [[{"class":"magi"}]],
    [[{"name":"Bob","class":{"invalid":true}}]], [[{"name":"Bob","level":false}]],
    [[{"name":"Bob","level":-2}]], string.rep("x", 1024 * 1024 + 1),
  }) do
    assert(n.lookup("Bob")); f.deliver(#f.downloads, body)
    eq(n.getclass("Bob"), "runewarden", "bad response preserves verified cache")
  end
  eq(count(f.events, "NameDB character updated"), event_count)
  assert(n.lookup("Bob")); local request = f.downloads[#f.downloads]
  e.raiseEvent("sysDownloadError", "HTTP 403", request.path)
  eq(n.getclass("Bob"), "runewarden")
  assert(n.lookup("Bob")); e.raiseEvent("sysDownloadError", f.downloads[#f.downloads].path, "HTTP 500")
  eq(n.getclass("Bob"), "runewarden")
  assert(n.lookup("Bob")); os.remove(f.downloads[#f.downloads].path)
  e.raiseEvent("sysDownloadDone", f.downloads[#f.downloads].path)
  eq(n.getclass("Bob"), "runewarden", "unreadable response")
  local foreign = os.tmpname()
  local out = assert(io.open(foreign, "w")); out:write("foreign"); out:close()
  e.raiseEvent("sysDownloadDone", foreign)
  eq(scalar(c, "SELECT class FROM people WHERE name='Bob'", "class"), "runewarden")
  local inp = assert(io.open(foreign)); eq(inp:read("*a"), "foreign", "foreign file untouched"); inp:close(); os.remove(foreign)
  assert(c:execute([[CREATE TRIGGER deny_magi BEFORE UPDATE OF class ON people WHEN NEW.class='magi' BEGIN SELECT RAISE(ABORT,'injected write failure'); END]])); assert(c:commit())
  assert(n.lookup("Bob")); f.deliver(#f.downloads, [[{"name":"Bob","class":"magi","city":"cyrene"}]])
  eq(n.getclass("Bob"), "runewarden"); eq(n.getcity("Bob"), "Ashtan", "atomic API rollback")
  eq(count(f.events, "NameDB character updated"), event_count)
  assert(c:execute("DROP TRIGGER deny_magi")); assert(c:commit())
  -- Cancel/timeout/reload/disconnect/delete/exit never resurrect late responses.
  assert(n.lookup("Bob")); local late = #f.downloads; n.cancel_lookups("Bob")
  f.deliver(late, [[{"name":"Bob","class":"magi"}]]); eq(n.getclass("Bob"), "runewarden")
  assert(n.lookup("Bob")); late = #f.downloads; f.world.advance(31)
  f.deliver(late, [[{"name":"Bob","class":"magi"}]]); eq(n.getclass("Bob"), "runewarden")
  assert(n.lookup("Bob")); late = #f.downloads; f.reload(); n = e.ndb
  f.deliver(late, [[{"name":"Bob","class":"magi"}]]); eq(n.getclass("Bob"), "runewarden")
  eq(count(f.events, "NameDB facts reset"), 1, "reload preserves verified cache and migration version")
  assert(n.lookup("Bob")); late = #f.downloads; e.raiseEvent("sysDisconnectionEvent")
  f.deliver(late, [[{"name":"Bob","class":"magi"}]]); eq(n.getclass("Bob"), "runewarden")
  assert(n.lookup("Bob")); late = #f.downloads
  n.lookup_online()
  local late_online = #f.downloads
  f.alias("(ndb delete person) Delete one individual entry", {"", "Bob"})
  f.deliver(late, [[{"name":"Bob","class":"magi"}]]); eq(n.exists("Bob"), false)
  eq(n.highlightIDs.Bob, nil, "deleted name no longer owns a live native highlight")
  f.deliver(late_online, [[{"count":1,"characters":[{"name":"Bob"}]}]])
  eq(n.exists("Bob"), false, "late online discovery cannot resurrect deleted person")
  -- Acquisition aliases all execute their actual source, without a game send.
  sends = #f.world.sent
  local acquisitions = {{"Who is", {"", "Whoisperson"}}, {"HTTP character lookup", {"", "Alice"}}, {"HTTP online list"}, {"qw-qw2"},
    {"(qwc) Organize by city members"}, {"(qw update) Re-check people on qw list"},
    {"HTTP unknown refresh"}, {"(ndb update all) Re-check every person in the database"},
    {"(ndb update unranked) Re-check all unranked players"}}
  for _, alias in ipairs(acquisitions) do
    n.cancel_lookups(); f.alias(alias[1], alias[2]); n.cancel_lookups()
  end
  eq(#f.world.sent, sends, "all lookup aliases have zero game commands")
  n.lookup_online()
  f.deliver(#f.downloads, [[{"count":3,"characters":[{"name":"Alice","uri":"https://evil.invalid/"},{"name":"alice"},{"name":"Bob"}]}]])
  eq(#n.last_online, 2, "online name dedup")
  eq(n.exists("Alice"), true); eq(n.exists("Bob"), true)
  local online_before = #f.downloads
  n.lookup_online(); n.lookup_online(true)
  eq(#f.downloads, online_before + 1, "online requests deduplicate")
  f.deliver(online_before + 1, [[{"count":2,"characters":[{"name":"Alice"},{"name":"Bob"}]}]])
  eq(#f.downloads, online_before + 3, "explicit refresh upgrades pending online request")
  n.cancel_lookups()
  for _, request in ipairs(f.downloads) do
    assert(request.url:match("^https://api%.achaea%.com/characters[/%.]"), "non-official download URL")
  end
  local entries = {}
  for i = 1, 400 do
    local suffix = string.char(65 + math.floor((i - 1) / 26), 97 + (i - 1) % 26)
    entries[#entries + 1] = '{"name":"Online' .. suffix .. '","uri":"https://api.achaea.com/characters/ignored.json"}'
  end
  local large_list = '{"count":400,"characters":[' .. table.concat(entries, ',') .. ']}'
  assert(#large_list > 10000)
  n.lookup_online(); f.deliver(#f.downloads, large_list)
  eq(#n.last_online, 400, "downloadFile supports online bodies larger than getHTTP event limit")
  n.cancel_lookups()
  local downloads = #f.downloads
  e.matches = {"", "Newperson"}
  f.trigger("Data Capture/Various common things/Newbie_spawned_-_reborn.lua")
  eq(#f.downloads, downloads + 1, "discovery starts its automatic HTTPS request")
  eq(f.downloads[#f.downloads].url, "https://api.achaea.com/characters/newperson.json")
  n.cancel_lookups()
  downloads = #f.downloads
  e.raiseEvent("NameDB got new data")
  eq(#f.downloads, downloads, "automatic discovery does not retry failed/cancelled names")
  -- Bulk cancellation also retires queued requests that were not yet started.
  for _, name in ipairs({"Alice", "Bob", "Carol", "David", "Edith", "Frank"}) do n.lookup(name) end
  downloads = #f.downloads; n.cancel_lookups(); f.world.advance(40)
  eq(#f.downloads, downloads, "cancel stops queued work")
  n.lookup("Cacheperson"); f.deliver(#f.downloads, [[{"name":"Cacheperson","class":"psion","city":"eleusis"}]])
  n.lookup("Exitperson"); late = #f.downloads
  e.raiseEvent("sysExitEvent")
  f.deliver(late, [[{"name":"Exitperson","class":"magi"}]])
  local reopened = fixture({profile = f.profile})
  eq(reopened.env.ndb.getclass("Cacheperson"), "psion", "verified cache survives a fresh DB connection")
  eq(count(reopened.events, "NameDB facts reset"), 0, "persistent migration marker")
  reopened.env.ndb.lookup("Rankperson")
  reopened.deliver(#reopened.downloads, [[{"name":"Rankperson","class":"magi","xp_rank":0}]])
  reopened.env.ndb.lookup("Rankperson")
  local rank_request = #reopened.downloads
  reopened.alias("(ndb delete unranked) Wipe all unranked (newbies and dormant) players")
  reopened.alias("(ndb delete unranked) Wipe all unranked (newbies and dormant) players")
  reopened.deliver(rank_request, [[{"name":"Rankperson","class":"magi","xp_rank":0}]])
  eq(reopened.env.ndb.exists("Rankperson"), false, "delete unranked retires pending responses")
  eq(reopened.env.ndb.getclass("Cacheperson"), "psion", "unranked deletion preserves ranked/unknown records")
  reopened.env.ndb.lookup("Deleteperson")
  local deleted_request = #reopened.downloads
  reopened.alias("(ndb delete all) Wipe the database clean")
  reopened.alias("(ndb delete all) Wipe the database clean")
  reopened.deliver(deleted_request, [[{"name":"Deleteperson","class":"magi"}]])
  eq(reopened.env.ndb.exists("Deleteperson"), false, "delete all retires all pending responses")
  -- A persisted disabled HONOURS-era setting cannot suppress non-blocking API work.
  local automatic = fixture({defer = true})
  local ae = automatic.env
  ae.svo.conf.autocheck = false
  automatic.reload()
  local an = ae.ndb
  an.addname("Autoperson")
  eq(#automatic.downloads, 1)
  eq(automatic.downloads[1].url, "https://api.achaea.com/characters/autoperson.json")
  automatic.deliver(1, [[{"name":"Autoperson","class":"magi","city":"ashtan"}]])
  eq(an.getclass("Autoperson"), "magi", "discovery publishes authoritative facts automatically")
  -- Old external settings may be reintroduced after load; they are not a gate.
  ae.svo.conf.autocheck = false
  an.lookup_online()
  automatic.deliver(2, [[{"count":2,"characters":[{"name":"Autoperson"},{"name":"Onlineperson"}]}]])
  eq(#automatic.downloads, 3, "ordinary online discovery fetches only unverified names")
  eq(automatic.downloads[3].url, "https://api.achaea.com/characters/onlineperson.json")
  automatic.deliver(3, [[{"name":"Onlineperson","class":"monk"}]])
  eq(an.getclass("Onlineperson"), "monk")
  ae.raiseEvent("NameDB got new data")
  eq(#automatic.downloads, 3, "verified names are not repeatedly fetched")
  eq(#automatic.world.sent, 0, "automatic lookups send no game commands")
  -- Bulk confirmation is based on matching records, not the whole database.
  for _, size in ipairs({99, 100}) do
    local bulk = fixture()
    local be, bn = bulk.env, bulk.env.ndb
    local people = {}
    for i = 1, size do
      people[#people + 1] = {name = "Bulk" .. string.char(65 + math.floor((i - 1) / 26), 97 + (i - 1) % 26)}
    end
    bn.merge_discovery(people)
    local bc = be.db.__conn.namedb
    assert(bc:execute("UPDATE people SET xp_rank=-2,api_verified=1")); assert(bc:commit())
    bn.merge_discovery({{name = "Rankedperson"}})
    assert(bc:execute("UPDATE people SET xp_rank=42 WHERE name='Rankedperson'")); assert(bc:commit())
    local alias = "(ndb update unranked) Re-check all unranked players"
    bulk.alias(alias)
    if size == 100 then
      eq(#bulk.downloads, 0, "large unranked refresh requires confirmation")
      bulk.alias(alias)
    end
    local seen, index = {}, 1
    while index <= #bulk.downloads do
      local name = assert(bulk.downloads[index].url:match("/characters/([a-z]+)%.json$"))
      assert(name ~= "rankedperson" and not seen[name], "refresh selects each unranked person once")
      seen[name] = true
      bulk.deliver(index, '{"name":"' .. name .. '","class":"magi","xp_rank":0}')
      index = index + 1
    end
    eq(#bulk.downloads, size, "all and only the matching refreshes completed")
    eq(bn.getclass("Bulkaa"), "magi", "confirmed requests committed actual API data")
    eq(#bulk.world.sent, 0, "bulk refresh never spends game balance")
    if size == 100 then
      bulk.alias(alias)
      eq(#bulk.downloads, size, "confirmation is consumed, not permanently latched")
    end
  end
  -- A separate old-schema DB injects an authority reset error, proving both the
  -- facts and authority marker roll back. Additive columns may safely remain.
  local r = fixture({defer = true})
  local re = r.env
  re.db:create("NameDB", {})
  local rc = re.db.__conn.namedb
  assert(rc:execute([[CREATE TABLE people (_row_id INTEGER PRIMARY KEY, name TEXT UNIQUE, class TEXT DEFAULT '')]]))
  assert(rc:execute([[INSERT INTO people(name,class) VALUES('Alice','monk')]]))
  assert(rc:execute([[CREATE TRIGGER deny_reset BEFORE UPDATE ON people BEGIN SELECT RAISE(ABORT,'reset denied'); END]])); assert(rc:commit())
  eq(pcall(r.reload), false, "authority migration failure surfaces")
  eq(scalar(rc, "SELECT class FROM people WHERE name='Alice'", "class"), "monk")
  eq(scalar(rc, "SELECT version FROM namedb_authority", "version"), nil, "version not recorded on rollback")
  -- Mudlet loads sibling scripts even after init reports an error. The native
  -- readers/highlighter must not expose rolled-back manual facts as API facts.
  r.continue_errors = true
  r.reload()
  eq(#r.script_errors, 1, "authority error remains visible while siblings load")
  eq(re.ndb.getclass("Alice"), "", "failed cutover exposes unknown, not manual class")
  eq(re.ndb.getname("Alice").class, "")
  eq(re.ndb.isclass("Alice", "monk"), false)
  eq(re.ndb.lookup("Alice"), nil, "acquisition waits for committed cutover")
  eq(#r.downloads, 0)
  eq(scalar(rc, "SELECT class FROM people WHERE name='Alice'", "class"), "monk", "failed-cutover projection does not overwrite SQLite")
  assert(rc:execute("DROP TRIGGER deny_reset")); assert(rc:commit()); r.reload()
  eq(re.ndb.getclass("Alice"), ""); eq(count(r.events, "NameDB facts reset"), 1)
end
local ok, err = xpcall(tests, debug.traceback)
for i = #fixtures, 1, -1 do pcall(fixtures[i].cleanup) end
if not ok then error(err) end
print(("NameDB: %d assertions (real SQLite + YAJL, native script metadata)"):format(checks))
