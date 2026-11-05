-- Official HTTPS API only. No game commands, balance listeners or retries.
-- A filename is an exact capability: URL substrings and response URIs confer
-- no ownership. Retired paths survive reload so late deliveries get discarded.
if ndb.cancel_lookups then ndb.cancel_lookups() end
local retired = ndb.http_retired or {}
ndb.http_retired = retired
local attempted = ndb.http_attempted or {}
ndb.http_attempted = attempted
local pending, queue, names = {}, {}, {}
local active, pumping = 0, false
local online_pending = false
local epoch = {}
ndb.http_epoch = epoch
local pump, settle

function ndb.canonical_name(name)
  if type(name) ~= "string" or #name < 3 or #name > 30 or not name:match("^[A-Za-z]+$") then
    return nil, "expected a character name (3-30 ASCII letters)"
  end
  return name:sub(1, 1):upper() .. name:sub(2):lower()
end

-- All non-API discovery paths may add names and personal policy, not facts.
function ndb.merge_discovery(rows)
  for _, source in ipairs(rows) do
    local name = ndb.canonical_name(source.name)
    if name then
      local fields = {}
      for key in pairs(ndb.policy_fields) do
        if source[key] ~= nil then fields[key] = source[key] end
      end
      local ok, err = ndb.transaction(function(c)
        local columns, values = {'name'}, {ndb.sql_literal(name)}
        for key, value in pairs(ndb.fact_defaults) do
          columns[#columns + 1] = '"' .. key .. '"'
          values[#values + 1] = ndb.sql_literal(value)
        end
        assert(c:execute('INSERT OR IGNORE INTO people(' .. table.concat(columns, ',') ..
          ') VALUES(' .. table.concat(values, ',') .. ')'))
        local assignments = {}
        for key, value in pairs(fields) do
          assignments[#assignments + 1] = '"' .. key .. '"=' .. ndb.sql_literal(value)
        end
        if #assignments > 0 then
          assert(c:execute('UPDATE people SET ' .. table.concat(assignments, ',') ..
            ' WHERE name=' .. ndb.sql_literal(name)))
        end
      end)
      assert(ok, err)
    end
  end
end

local function text(value, lower)
  if value == nil or value == yajl.null then return "" end
  assert(type(value) == "string" and #value <= 1000, "invalid textual character field")
  local normalized = value:match("^%s*(.-)%s*$"):lower()
  if normalized == "" or normalized == "(hidden)" or normalized == "hidden" then return "" end
  return lower and normalized or value
end
local function number(value)
  if value == nil or value == yajl.null then return -1 end
  assert(type(value) == "number" or type(value) == "string", "invalid numeric character field")
  if type(value) == "string" then
    local normalized = value:match("^%s*(.-)%s*$"):lower()
    if normalized == "" or normalized == "(hidden)" or normalized == "hidden"
        or normalized == "(none)" or normalized == "none" then return -1 end
  end
  local n = tonumber(value)
  assert(n and n == n and n >= 0 and n < 1e12 and n == math.floor(n),
    "invalid numeric character field")
  return n
end
local function facts(data, requested)
  if type(data) ~= "table" or ndb.canonical_name(data.name) ~= requested then
    error("character response name does not match request")
  end
  local result = {}
  for key, value in pairs(ndb.fact_defaults) do result[key] = value end
  result.title = text(data.fullname)
  result.class = text(data.class, true)
  if result.class == "(none)" or result.class == "none" or result.class == "unknown" then result.class = "" end
  local city = text(data.city, true)
  if city == "(none)" or city == "none" then result.city = "rogue"
  elseif city == "underworld" then result.city = "Undead"
  elseif city ~= "" and city ~= "unknown" then result.city = city:sub(1, 1):upper() .. city:sub(2) end
  local house = text(data.house)
  if house ~= "(none)" and house:lower() ~= "none" then
    result.guild = house:sub(1, 1):upper() .. house:sub(2)
  end
  result.level, result.xp_rank = number(data.level), number(data.xp_rank)
  result.mob_kills = text(data.mob_kills)
  result.player_kills, result.explorer_rank = number(data.player_kills), number(data.explorer_rank)
  if result.xp_rank == 0 then result.xp_rank = -2 end
  result.api_verified, result.api_updated = 1, os.time()
  return result
end
local function commit_character(data, name)
  local values = facts(data, name)
  local ok, err = ndb.transaction(function(c)
    -- Deletion cancels before removing the row, but never resurrect a row here.
    local assignments = {}
    for key, value in pairs(values) do
      assignments[#assignments + 1] = '"' .. key .. '"=' .. ndb.sql_literal(value)
    end
    local changed = assert(c:execute('UPDATE people SET ' .. table.concat(assignments, ',') ..
      ' WHERE name=' .. ndb.sql_literal(name)))
    assert(changed ~= 0, "character was deleted before response")
  end)
  assert(ok, err)
  raiseEvent("NameDB character updated", name)
end
local function online(data, refresh)
  if type(data) ~= "table" or type(data.characters) ~= "table" or
      type(data.count) ~= "number" or data.count ~= #data.characters then
    error("invalid online list")
  end
  local list, seen = {}, {}
  for _, entry in ipairs(data.characters) do
    if type(entry) ~= "table" then error("invalid online character") end
    local name = ndb.canonical_name(entry.name)
    if not name then error("invalid online character name") end
    if not seen[name] then list[#list + 1] = {name = name}; seen[name] = true end
  end
  ndb.merge_discovery(list)
  ndb.last_online = {}
  for _, entry in ipairs(list) do
    ndb.last_online[#ndb.last_online + 1] = entry.name
    local person = ndb.getname(entry.name)
    if refresh or (person.api_verified ~= 1 and not attempted[entry.name]) then
      ndb.lookup(entry.name)
    end
    raiseEvent("NameDB saw list name", entry.name)
  end
  ndb.show_online()
end

settle = function(request, outcome, data)
  if request.done then return end
  request.done = true
  if request.timer then killTimer(request.timer) end
  if request.path then
    pending[request.path] = nil
    retired[request.path] = true
    os.remove(request.path)
    active = active - 1
  end
  if request.name then names[request.name] = nil
  else
    online_pending = false
    if outcome ~= "success" then ndb.qwtype = nil end
  end
  if outcome == "success" and ndb.http_epoch == epoch then
    local ok, err = pcall(function()
      if request.name then commit_character(data, request.name) else online(data, request.refresh) end
    end)
    if not ok then
      if not request.name then ndb.qwtype = nil end
      svo.echof("NameDB lookup failed: %s", tostring(err))
    end
  elseif outcome ~= "cancel" then
    svo.echof("NameDB lookup failed for %s: %s", request.name or "online list", tostring(data or outcome))
  end
  pump()
end
local function owned_path()
  while true do
    local path = os.tmpname()
    if not pending[path] and not retired[path] then return path end
    -- os.tmpname reserved this file, but a removed historical name may recur.
    os.remove(path)
  end
end
pump = function()
  if pumping or ndb.http_epoch ~= epoch then return end
  pumping = true
  while active < 3 and #queue > 0 do
    local request = table.remove(queue, 1)
    if not request.done then
      local reserved, path = pcall(owned_path)
      if not reserved then
        settle(request, "error", path)
      else
        request.path = path
        pending[path] = request
        active = active + 1
        request.timer = tempTimer(30, function() settle(request, "timeout") end)
        local url = request.name and
          ("https://api.achaea.com/characters/" .. request.name:lower() .. ".json") or
          "https://api.achaea.com/characters.json"
        local ok, result = pcall(downloadFile, path, url)
        if not ok or result == false then settle(request, "error", result) end
      end
    end
  end
  pumping = false
end
function ndb.lookup(name)
  if not ndb.authority_ready then return nil, "NameDB authority migration has not completed" end
  local canonical, err = ndb.canonical_name(name)
  if not canonical then return nil, err end
  if names[canonical] then return true, "already pending" end
  ndb.merge_discovery({{name = canonical}})
  attempted[canonical] = true
  local request = {name = canonical}
  names[canonical], queue[#queue + 1] = request, request
  pump()
  return true
end
function ndb.lookup_online(refresh)
  if not ndb.authority_ready then return nil, "NameDB authority migration has not completed" end
  if online_pending then
    online_pending.refresh = online_pending.refresh or refresh
    return true, "already pending"
  end
  local request = {refresh = refresh}
  online_pending, queue[#queue + 1] = request, request
  pump()
  return true
end
function ndb.refresh(scope)
  for _, person in ipairs(db:fetch(ndb.db.people)) do
    if scope == "all" or (scope == "unranked" and person.xp_rank == -2) or
        ((scope == nil or scope == "new") and person.api_verified ~= 1) then
      ndb.lookup(person.name)
    end
  end
end
function ndb.autodiscover()
  for _, person in ipairs(db:fetch(ndb.db.people)) do
    local name = ndb.canonical_name(person.name)
    if name and person.api_verified ~= 1 and not attempted[name] then ndb.lookup(name) end
  end
end
function ndb.cancel_lookups(name)
  local canonical = name and ndb.canonical_name(name)
  if name and not canonical then return end
  pumping = true
  for _, request in pairs(names) do
    if not canonical or request.name == canonical then settle(request, "cancel") end
  end
  if not canonical then
    ndb.qwtype = nil
    for _, request in pairs(pending) do if not request.name then settle(request, "cancel") end end
    for _, request in ipairs(queue) do if not request.done then settle(request, "cancel") end end
    queue = {}
  end
  pumping = false
  pump()
end
function ndb.http_lifecycle()
  ndb.cancel_lookups()
end
function ndb.downloaded_file(event, ...)
  local path, request
  for i = 1, select("#", ...) do
    local value = select(i, ...)
    if type(value) == "string" and (pending[value] or retired[value]) then
      path, request = value, pending[value]
      break
    end
  end
  if not path then return end
  if not request then os.remove(path); return end
  if event ~= "sysDownloadDone" then settle(request, "error", "download failed"); return end
  local file, err = io.open(path, "rb")
  if not file then settle(request, "error", err); return end
  local body = file:read(1024 * 1024 + 1)
  file:close()
  if not body or #body > 1024 * 1024 then settle(request, "error", "response exceeds 1 MiB"); return end
  local ok, data = pcall(yajl.to_value, body)
  if not ok then settle(request, "error", "invalid JSON"); return end
  settle(request, "success", data)
end
