-- Native skill-discovery regressions. Run from Sources/svof:
--   lua tools/test_skill_discovery.lua
-- Loads the shipped loaders and Config_system consumers through svof_world.
-- Only Mudlet I/O (including the JSON encoder) is supplied by this harness.
-- Does not prove live game wording or Mudlet event delivery.
local world = dofile("tools/svof_world.lua")
local checks, failures = 0, {}
local function eq(actual, expected, label)
  checks = checks + 1
  if actual ~= expected then
    failures[#failures + 1] = label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual)
  end
end
local canonical = {"focus", "restore", "breath", "clot", "insomnia", "efficiency", "thirdeye", "deathsight",
  "fitness", "rage", "parry", "guarding", "recoverfooting", "shindoblind", "shindodeaf"}
local survival = {
  {"focus", "focusing", true}, {"restore", "restoration", false}, {"breath", "breathing", false},
  {"clot", "clotting", true}, {"insomnia", "insomnia", true}, {"efficiency", "efficiency", true},
}
local function prepare(class, preferences)
  local w = world.new({class = class or "Runewarden"})
  for _, key in ipairs(canonical) do w.svo.conf[key] = nil end
  for key, value in pairs(preferences or {}) do w.svo.conf[key] = value end
  w.svo.sys.enabledgmcp = true
  w.env.gmcp.Char.Status = {city = "", level = "80"}
  w.env.gmcp.Char.Skills = {}
  w.requests = {}
  w.env.yajl = {to_string = function(t)
    -- These requests have only string-valued group/name fields.
    local fields = {}
    for _, key in ipairs({"group", "name"}) do
      if t[key] then fields[#fields + 1] = '"' .. key .. '":"' .. t[key] .. '"' end
    end
    return "{" .. table.concat(fields, ",") .. "}"
  end}
  w.env.sendGMCP = function(command) w.requests[#w.requests + 1] = command end
  return w
end
local function start(class, preferences)
  local w = prepare(class, preferences)
  w.svo.installstart()
  return w
end
local function requested(w, group, name)
  for _, command in ipairs(w.requests) do
    if command:find('"group":"' .. group .. '"', 1, true)
      and command:find('"name":"' .. name .. '"', 1, true) then return true end
  end
  return false
end
local function info(w, group, skill, description)
  local packet = {group = group, skill = skill, info = description}
  w.env.gmcp.Char.Skills.Info = packet
  w.svo.signals.gmcpcharskillsinfo:emit()
  eq(packet.skill, skill, "Info packet skill is immutable: " .. skill)
  eq(packet.group, group, "Info packet group is immutable: " .. skill)
  eq(packet.info, description, "Info packet body is immutable: " .. skill)
end
local function list(w, group, names)
  w.env.gmcp.Char.Skills.List = {group = group, list = names}
  w.svo.signals.gmcpcharskillslist:emit()
end
local function gained(w, group, skill) info(w, group, skill, "Syntax: " .. skill:upper()) end
local function unavailable(w, group, skill) info(w, group, skill, "You have not yet learned this ability.") end
local function settle_survival_info(w)
  for _, row in ipairs(survival) do
    if row[3] then gained(w, "survival", row[2]) else unavailable(w, "survival", row[2]) end
  end
end
local function settle_survival_list(w)
  list(w, "Survival", {"Focusing", "Clotting", "Insomnia", "Efficiency"})
end
local function snapshot(w)
  local state = {}
  for _, row in ipairs(survival) do
    state[#state + 1] = row[1] .. "=" .. tostring(w.svo.conf[row[1]]) .. "/" .. tostring(w.svo.install.ids[row[1]])
  end
  return table.concat(state, ",")
end

-- The actual requested Info names, not the config names, must settle all
-- pending IDs immediately. A later fallback List must not change that result.
local reference
for _, order in ipairs({"info-first", "list-first", "interleaved"}) do
  local w = start()
  for _, row in ipairs(survival) do
    eq(requested(w, "survival", row[2]), true, order .. ": requested " .. row[2])
    eq(w.svo.install.ids[row[1]], true, order .. ": canonical pending " .. row[1])
  end
  if order == "info-first" then
    settle_survival_info(w)
    for _, row in ipairs(survival) do
      eq(w.svo.install.ids[row[1]], nil, "Info alone settles " .. row[1])
    end
    settle_survival_list(w)
  elseif order == "list-first" then
    settle_survival_list(w)
    settle_survival_info(w)
  else
    gained(w, "SURVIVAL", "Focusing")
    settle_survival_list(w)
    settle_survival_info(w)
  end
  for _, row in ipairs(survival) do
    eq(w.svo.conf[row[1]], row[3], order .. ": learned flag " .. row[1])
    eq(w.svo.install.ids[row[1]], nil, order .. ": completed " .. row[1])
  end
  for _, wrong in ipairs({"focusing", "restoration", "breathing", "clotting"}) do
    eq(w.svo.conf[wrong], nil, order .. ": no novel config " .. wrong)
  end
  reference = reference or snapshot(w)
  eq(snapshot(w), reference, order .. ": same final flags and IDs")
end

-- Both known-unlearned forms complete the canonical request without List.
for _, description in ipairs({"", "You have not yet learned this ability."}) do
  local w = start()
  info(w, "survival", "focusing", description)
  eq(w.svo.conf.focus, false, "unlearned Info disables unknown focus")
  eq(w.svo.install.ids.focus, nil, "unlearned Info completes focus")
  eq(w.svo.install.ids.breath, true, "unlearned Info leaves other request pending")
end

-- Non-fresh detection and either response order preserve explicit preferences.
for _, first in ipairs({"info", "list"}) do
  local w = start("Runewarden", {focus = false, breath = false, restore = true})
  eq(w.svo.conf.focus, false, "start preserves explicit focus off")
  eq(w.svo.conf.restore, true, "start preserves explicit restore on")
  if first == "list" then settle_survival_list(w) end
  settle_survival_info(w)
  settle_survival_list(w)
  eq(w.svo.conf.focus, false, first .. ": learned focus preserves preference off")
  eq(w.svo.conf.restore, true, first .. ": unavailable restore does not rewrite explicit preference")
  eq(w.svo.conf.breath, false, first .. ": unavailable breath remains off")
  eq(w.svo.install.ids.focus, nil, first .. ": preference still completes pending request")
end

-- Blocked signals, unrequested skills, wrong groups and malformed packets
-- cannot write config or accidentally finish a similarly named request.
do
  local w = prepare()
  gained(w, "survival", "focusing")
  eq(w.svo.conf.focus, nil, "outside installation signal stays blocked")
  w.svo.installstart()
  w.svo.signals.gmcpcharskillsinfo:block(w.svo.install.checkskillgmcp)
  gained(w, "survival", "focusing")
  eq(w.svo.conf.focus, nil, "explicitly blocked Info leaves focus unknown")
  eq(w.svo.install.ids.focus, true, "blocked Info leaves request pending")
  w.svo.signals.gmcpcharskillsinfo:unblock(w.svo.install.checkskillgmcp)
  gained(w, "vision", "focusing")
  gained(w, "survival", "madeup")
  gained(w, "shindo", "blind")
  list(w, "unrelated", {"Focusing", "Breathing"})
  eq(w.svo.conf.focus, nil, "wrong groups leave canonical focus untouched")
  eq(w.svo.conf.madeup, nil, "unknown skill cannot create config")
  eq(w.svo.conf.blind, nil, "unrequested class skill cannot create config")
  eq(w.svo.install.ids.focus, true, "wrong groups cannot complete focus")
  w.env.gmcp.Char.Skills.Info = {group = "survival", skill = "focusing"}
  w.svo.signals.gmcpcharskillsinfo:emit()
  w.env.gmcp.Char.Skills.List = {group = "survival"}
  w.svo.signals.gmcpcharskillslist:emit()
  eq(w.svo.install.ids.focus, true, "incomplete packets leave requests pending")
  gained(w, "survival", "focusing")
  eq(w.svo.conf.focus, true, "correct pending Info is accepted")
  unavailable(w, "survival", "focusing")
  list(w, "survival", {})
  eq(w.svo.conf.focus, true, "duplicate and late replies cannot overwrite settled flag")
end

-- Class requests use their real consumer names, never broad skill aliases.
for _, method in ipairs({"info", "list"}) do
  local w = start("Runewarden")
  eq(requested(w, "weaponmastery", "recover"), true, method .. ": actual Recover request")
  if method == "info" then gained(w, "weaponmastery", "recover")
  else list(w, "weaponmastery", {"Recover"}) end
  eq(w.svo.conf.recoverfooting, true, method .. ": Recover enables recoverfooting")
  eq(w.svo.conf.recover, nil, method .. ": no recover config alias")
  eq(w.svo.install.ids.recoverfooting, nil, method .. ": Recover completes canonical ID")

  w = start("Blademaster")
  eq(requested(w, "shindo", "blind"), true, method .. ": actual Shindo blind request")
  eq(requested(w, "shindo", "deaf"), true, method .. ": actual Shindo deaf request")
  if method == "info" then gained(w, "shindo", "blind"); unavailable(w, "shindo", "deaf")
  else list(w, "shindo", {"Blind"}) end
  eq(w.svo.conf.shindoblind, true, method .. ": Shindo blind consumer")
  eq(w.svo.conf.shindodeaf, false, method .. ": Shindo deaf unavailable")
  eq(w.svo.conf.blind, nil, method .. ": no blind config alias")
  eq(w.svo.conf.deaf, nil, method .. ": no deaf config alias")
  eq(w.svo.install.ids.shindoblind, nil, method .. ": Shindo blind completed")
  eq(w.svo.install.ids.shindodeaf, nil, method .. ": Shindo deaf completed")

  w = start("Monk")
  eq(requested(w, "tekura", "guarding"), true, method .. ": actual Tekura guarding request")
  eq(w.svo.install.ids.guarding, true, method .. ": canonical guarding pending")
  eq(w.svo.install.ids.parry, nil, method .. ": Tekura did not request parry")
  if method == "info" then gained(w, "tekura", "guarding")
  else list(w, "tekura", {"Guarding"}) end
  eq(w.svo.conf.guarding, true, method .. ": real guarding consumer enabled")
  eq(w.svo.conf.parry, nil, method .. ": guarding never aliases to parry")
  eq(w.svo.install.ids.guarding, nil, method .. ": guarding completed")
end

-- Native class reload invalidates the old discovery scope and its timeout.
do
  local w = start("Blademaster")
  gained(w, "survival", "focusing") -- arms the installation fallback timer
  w.svo.classchange("Runewarden")
  eq(next(w.svo.install.ids), nil, "class reload retires old pending IDs")
  w.svo.conf.shindoblind, w.svo.conf.shindodeaf = nil, nil
  w.advance(6)
  eq(w.svo.conf.shindoblind, nil, "old timeout cannot disable previous class flag")
  gained(w, "shindo", "blind")
  eq(w.svo.conf.shindoblind, nil, "old response is ignored after native class reload")
  w.svo.conf.recoverfooting = nil
  w.svo.installstart()
  gained(w, "shindo", "deaf")
  eq(w.svo.conf.shindodeaf, nil, "new run ignores previous class response")
  gained(w, "weaponmastery", "recover")
  eq(w.svo.conf.recoverfooting, true, "new class request completes normally")
end

-- Restarting discovery retires the prior pending table; fallback expiry must
-- not disable a user preference or a completed request in the replacement run.
do
  local w = start("Runewarden", {breath = false})
  gained(w, "survival", "focusing")
  local old = w.svo.install.ids
  w.svo.installstart()
  eq(w.svo.install.ids == old, false, "restart owns a fresh pending table")
  unavailable(w, "survival", "restoration")
  w.advance(6)
  eq(w.svo.conf.focus, true, "fallback preserves previously enabled preference")
  eq(w.svo.conf.breath, false, "fallback preserves explicit false preference")
  eq(w.svo.conf.restore, false, "fallback preserves settled unavailable ability")
  eq(w.svo.install.ids.restore, nil, "fallback leaves completed ID absent")
end

-- An explicitly confirmed fresh install, unlike re-detection, resets choices.
do
  local w = prepare("Runewarden", {focus = false})
  w.svo.sk.installwarning = true
  w.svo.installstart(true)
  eq(w.svo.conf.focus, nil, "confirmed fresh install resets discovered preference")
  gained(w, "survival", "focusing")
  eq(w.svo.conf.focus, true, "fresh install can discover focus after reset")
end

-- The separately requested morph group also belongs to this run, rather than
-- letting a late AB list overwrite a user's selected morph.
do
  local w = prepare("Druid")
  w.svo.conf.morphskill = nil
  list(w, "metamorphosis", {"Hydra"})
  eq(w.svo.conf.morphskill, nil, "unsolicited morph List cannot write config")
  w.svo.installstart()
  eq(w.svo.install.ids.morphskill, true, "morph group has its own pending ID")
  w.svo.conf.morphskill = "wolf"
  list(w, "Metamorphosis", {"Hydra"})
  eq(w.svo.conf.morphskill, "wolf", "morph response preserves explicit choice")
  eq(w.svo.install.ids.morphskill, nil, "morph response completes its own request")
  w.svo.conf.morphskill = nil
  list(w, "metamorphosis", {"Hydra"})
  eq(w.svo.conf.morphskill, nil, "late settled morph List is ignored")
  w.svo.conf.morphskill = "wolf"
  w.svo.sk.installwarning = true
  w.svo.installstart(true)
  eq(w.svo.conf.morphskill, nil, "confirmed fresh install resets morph preference")
  list(w, "Metamorphosis", {"Hydra"})
  eq(w.svo.conf.morphskill, "hydra", "fresh discovery replaces the old morph ceiling")
  eq(w.svo.install.ids.morphskill, nil, "fresh morph discovery completes")
end

for _, failure in ipairs(failures) do print("FAIL " .. failure) end
print(string.format("%d checks, %d failures", checks, #failures))
if #failures > 0 then os.exit(1) end
print("ALL PASS")
