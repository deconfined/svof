-- Identity facts belong exclusively to the official character API. Personal
-- policies and annotations are deliberately outside this set.
ndb.fact_defaults = {
  title = "", gender = "", class = "", city = "", city_rank = 0,
  city_soldier = -1, guild = "", might = -1, xp_rank = -1, level = -1,
  immortal = -1, order = "", dragon = -1, mark = "", race = "",
  combat_rank = -1, combat_rating = -1, birth_day = 0, birth_month = 0,
  birth_year = 0, birth_hidden = -1, arms = "", divorces = -1,
  motto = "", warcry = "", infamous = -1, api_verified = 0, api_updated = 0,
  mob_kills = "", player_kills = -1, explorer_rank = -1,
}
ndb.policy_fields = { notes = true, iff = true, importance = true,
  cityenemy = true, orderenemy = true, houseenemy = true }
ndb.schema = { people = { name = "", importance = 0, iff = -1,
  cityenemy = 0, orderenemy = 0, houseenemy = 0, notes = "",
  _unique = {"name"}, _violations = "FAIL" } }
for key, value in pairs(ndb.fact_defaults) do ndb.schema.people[key] = value end

local function ident(value) return '"' .. value:gsub('"', '""') .. '"' end
local function literal(value)
  if type(value) == "number" then return tostring(value) end
  return "'" .. value:gsub("'", "''") .. "'"
end
ndb.sql_literal = literal

function ndb.transaction(fn)
  local conn = db.__conn.namedb
  local ok, result = pcall(fn, conn)
  if ok then
    local committed, err = conn:commit()
    if committed then return true, result end
    result = err or "commit failed"
  end
  conn:rollback()
  return nil, result
end

function ndb.init()
  ndb.authority_ready = false
  -- Open without handing db:_migrate an incomplete schema: its redundant-column
  -- path rebuilds tables. Add missing columns only, preserving custom schema,
  -- indexes, triggers, row IDs and all personal data, even on an empty old DB.
  local previous = db.__schema.namedb
  db:create("NameDB", {})
  if previous then db.__schema.namedb = previous end
  local conn = db.__conn.namedb
  local columns = {}
  local cursor = assert(conn:execute("PRAGMA table_info(people)"))
  local row = cursor:fetch({}, "a")
  while row do columns[row.name] = row.type; row = cursor:fetch({}, "a") end
  cursor:close()
  local ok, err = ndb.transaction(function(c)
    if not next(columns) then
      assert(c:execute('CREATE TABLE people (_row_id INTEGER PRIMARY KEY AUTOINCREMENT)'))
    end
    for key, value in pairs(ndb.schema.people) do
      if key:sub(1, 1) ~= "_" and not columns[key] then
        assert(c:execute('ALTER TABLE people ADD COLUMN ' .. ident(key) ..
          (type(value) == "number" and ' REAL' or ' TEXT') .. ' DEFAULT ' .. literal(value)))
      end
    end
    assert(c:execute('CREATE UNIQUE INDEX IF NOT EXISTS namedb_http_people_name ON people(name)'))
    assert(c:execute('CREATE TABLE IF NOT EXISTS namedb_authority (version INTEGER NOT NULL)'))
  end)
  assert(ok, err)
  -- Register a native Mudlet sheet without invoking its destructive redundant-
  -- column migration. Include custom columns solely for native fetch coercion.
  local registered = {columns = {}, options = {_unique = {"name"}, _violations = "FAIL"}}
  local old_people = previous and previous.people
  for key, value in pairs(old_people and old_people.options or {}) do
    if key ~= "_unique" and key ~= "_violations" then registered.options[key] = value end
  end
  for key, value in pairs(ndb.schema.people) do
    if key:sub(1, 1) ~= "_" then registered.columns[key] = value end
  end
  for key, kind in pairs(columns) do
    if key ~= "_row_id" and registered.columns[key] == nil then
      local numeric = kind:upper():find("INT") or kind:upper():find("REAL") or kind:upper():find("NUM")
      local old_default = old_people and old_people.columns[key]
      if old_default ~= nil then registered.columns[key] = old_default
      else registered.columns[key] = numeric and 0 or "" end
    end
  end
  db.__schema.namedb.people = registered
  ndb.db = db:get_database("NameDB")
  local reset = false
  ok, err = ndb.transaction(function(c)
    local versions = assert(c:execute('SELECT version FROM namedb_authority'))
    local current = versions:fetch({}, "a")
    versions:close()
    if current and tonumber(current.version) >= 1 then return end
    local assignments = {}
    for key, value in pairs(ndb.fact_defaults) do
      assignments[#assignments + 1] = ident(key) .. '=' .. literal(value)
    end
    assert(c:execute('UPDATE people SET ' .. table.concat(assignments, ',')))
    assert(c:execute('DELETE FROM namedb_authority'))
    assert(c:execute('INSERT INTO namedb_authority(version) VALUES(1)'))
    reset = true
  end)
  assert(ok, err)
  ndb.authority_ready = true
  if reset then ndb.pending_facts_reset = true end
end

ndb.init()
