-- Real native NameDB scripts, loaded in ScriptGroup/metadata order, on the
-- unmodified pinned Mudlet DB.lua and actual LuaSQL SQLite + YAJL providers.
local source = debug.getinfo(1, "S").source:sub(2)
local root = source:match("^(.*)tools/namedb_fixture%.lua$") or error("cannot locate fixture root")
local DB = dofile(root .. "tools/namedb_db.lua")
local M = {}
local function file(path)
  local handle = assert(io.open(path, "rb"))
  local contents = handle:read("*a"); handle:close(); return contents
end
local function run(code, path, env)
  local chunk
  if setfenv then chunk = assert(loadstring(code, "@" .. path)); setfenv(chunk, env)
  else chunk = assert(load(code, "@" .. path, "t", env)) end
  return chunk()
end
local function json_provider()
  local ok, provider = pcall(require, "yajl")
  if not ok then
    local home, version = os.getenv("HOME"), _VERSION:match("(%d+%.%d+)")
    package.cpath = home .. "/.luarocks/lib/lua/" .. version .. "/?.so;" .. package.cpath
    ok, provider = pcall(require, "yajl")
  end
  assert(ok, "Install the real lua-yajl provider for this Lua: luarocks install lua-yajl --local\n" .. tostring(provider))
  return provider
end
function M.install(env, options)
  options = options or {}
  local world
  if not env then
    world = dofile(root .. "tools/svof_world.lua").new({class = "Runewarden"})
    env = world.env
  end
  local state = {env = env, world = world, downloads = {}, events = {}, loaded = {}, metadata = {}}
  state.continue_errors = options.continue_errors
  state.script_errors = {}
  env.ndb = nil -- discard the host helper's fixture-only NameDB, never shadow native reads
  env.os = os
  env.display = env.display or function() end
  env.ioprint = env.ioprint or function() end
  state.prompt_appends = {}
  env.appendBuffer = env.appendBuffer or function(window)
    state.prompt_appends[#state.prompt_appends + 1] = window or "main"
  end
  env.dinsertText = env.dinsertText or env.decho
  env.yajl = json_provider()
  env.svo.me.watchfor = env.svo.me.watchfor or {}
  env.svo.me.highlightignore = env.svo.me.highlightignore or {}
  local database = DB.install(env, options)
  state.profile, state.db = database.profile, database.db
  -- The provider and parser are real. Only client I/O, timers and static event
  -- dispatch are controlled by this fixture, as Mudlet itself is not running.
  env.downloadFile = function(path, url)
    state.downloads[#state.downloads + 1] = {path = path, url = url}
    return true
  end
  local original_raise = env.raiseEvent
  local function resolve(name)
    local value = env
    for part in name:gmatch("[^.]+") do value = value and value[part] end
    return value
  end
  env.raiseEvent = function(event, ...)
    state.events[#state.events + 1] = {name = event, args = {...}}
    if original_raise then original_raise(event, ...) end
    for _, record in ipairs(state.metadata) do
      for _, registered in ipairs(record.eventHandlerList or {}) do
        if registered == event then
          local fn = resolve(record.name)
          assert(type(fn) == "function", "missing native event function " .. record.name)
          fn(event, ...)
        end
      end
    end
  end
  local function filename(name) return (name:gsub("[ /\\:*?\"<>|]", "_")) .. ".lua" end
  local function exists(path) local f = io.open(path); if f then f:close(); return true end end
  local function script(code, path)
    if not state.continue_errors then return run(code, path, env) end
    local ok, err = pcall(run, code, path, env)
    if not ok then state.script_errors[#state.script_errors + 1] = {path = path, error = err} end
  end
  local function walk(dir, records)
    for _, record in ipairs(records) do
      local path = dir .. filename(record.name)
      if record.script then script(record.script, path)
      elseif exists(path) then script(file(path), path); state.loaded[#state.loaded + 1] = path end
      state.metadata[#state.metadata + 1] = record
      if record.children then walk(dir, record.children) end
      if record.isFolder == "yes" then
        local sub = dir .. record.name .. "/"
        if exists(sub .. "scripts.json") then walk(sub, env.yajl.to_value(file(sub .. "scripts.json"))) end
      end
    end
  end
  function state.reload()
    state.metadata, state.loaded = {}, {}
    state.script_errors = {}
    walk(root .. "src/scripts/svo (namedb)/", env.yajl.to_value(file(root .. "src/scripts/svo (namedb)/scripts.json")))
  end
  function state.deliver(index, body, event)
    local request = assert(state.downloads[index], "no such download")
    local out = assert(io.open(request.path, "wb")); out:write(body); out:close()
    env.raiseEvent(event or "sysDownloadDone", request.path)
  end
  function state.alias(name, captures)
    local dir = root .. "src/aliases/svo (namedb)/NameDB/"
    local records = env.yajl.to_value(file(dir .. "aliases.json"))
    for _, record in ipairs(records) do
      if record.name == name then
        env.matches = captures or {}
        run(record.script or file(dir .. filename(name)), dir .. filename(name), env)
        return
      end
    end
    error("no native alias " .. name)
  end
  function state.trigger(path)
    run(file(root .. "src/triggers/svo (namedb)/" .. path), path, env)
  end
  function state.cleanup()
    if state.closed then return end
    state.closed = true
    if env.ndb and env.ndb.cancel_lookups then env.ndb.cancel_lookups() end
    for _, request in ipairs(state.downloads) do os.remove(request.path) end
    env.raiseEvent = original_raise
    database.cleanup()
  end
  if not options.defer then
    local ok, err = pcall(state.reload)
    if not ok then state.cleanup(); error(err, 0) end
  end
  return state
end
return M
