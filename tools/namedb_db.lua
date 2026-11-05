-- Actual Mudlet DB.lua + LuaSQL/SQLite, isolated to a temporary profile directory.
-- Test-only: no production package contains this fixture or the vendored provider.
local source = debug.getinfo(1, "S").source:sub(2)
local root = source:match("^(.*)tools/namedb_db%.lua$") or error("cannot locate fixture root")
local M = {}
local function quote(value) return "'" .. value:gsub("'", "'\\''") .. "'" end
local function success(ok, _, code) return ok == true or ok == 0 or code == 0 end
local function sqlite_driver()
  local ok, driver = pcall(require, "luasql.sqlite3")
  -- LuaRocks --local uses this standard tree; do not require a shell eval merely
  -- to run the verifier. The ABI directory must match the running interpreter.
  local home, version = os.getenv("HOME"), _VERSION:match("(%d+%.%d+)")
  if not ok and home and version then
    package.cpath = home .. "/.luarocks/lib/lua/" .. version .. "/?.so;" .. package.cpath
    ok, driver = pcall(require, "luasql.sqlite3")
  end
  assert(ok, "Install the real SQLite driver for this Lua: luarocks --lua-version=" ..
    tostring(version) .. " install luasql-sqlite3 2.6.0-2 --local\n" .. tostring(driver))
  assert(type(driver._VERSION) == "string" and driver._VERSION:find("LuaSQL 2.6.0 ", 1, true),
    "The pinned Mudlet DB fixture requires LuaSQL 2.6.0-2; 2.8 has an incompatible empty PRAGMA cursor")
  return driver
end

function M.install(env, options)
  assert(type(env) == "table", "pass the real svof world's Mudlet environment")
  options = options or {}
  local profile, owned = options.profile, options.profile == nil
  if owned then
    profile = os.tmpname()
    os.remove(profile)
    assert(success(os.execute("mkdir " .. quote(profile))), "cannot create temporary profile")
  else
    -- Reopen only scratch profiles, never a real Mudlet profile/database.
    local tmp = os.getenv("TMPDIR") or "/tmp/"
    assert(profile:sub(1, #tmp) == tmp or profile:sub(1, 5) == "/tmp/",
      "database fixture refuses a non-temporary profile")
  end
  env.luasql = sqlite_driver()
  env.getMudletHomeDir = function() return profile end
  local base_io = io
  env.io = setmetatable({ exists = function(path)
    local handle = base_io.open(path, "rb")
    if not handle then return false end
    handle:close()
    return true
  end }, { __index = base_io })
  -- These are normal Lua facilities, not substitutes for DB behavior.
  env.package, env.require = package, require
  local path = root .. "tools/testfixtures/DB.lua"
  local chunk
  if setfenv then
    chunk = assert(loadfile(path)); setfenv(chunk, env)
  else
    chunk = assert(loadfile(path, "t", env))
  end
  chunk()
  local state = { profile = profile, db = env.db }
  function state.cleanup()
    if state.closed then return end
    state.closed = true
    if state.db.__env then state.db:close() end
    if owned then
      assert(success(os.execute("rm -rf " .. quote(profile))), "cannot remove temporary profile")
    end
  end
  return state
end

return M
