--[[
Real-source parry regression: loads the native policy, dictionary, action
scheduler and public setup API through svof_world. Only Mudlet I/O is stubbed.
Run from Sources/svof: lua tools/test_parry_policy.lua
No percentage-based policy or new tactical choices are exercised here.
]]
local world = dofile("tools/svof_world.lua")
local checks, failures = 0, {}
local function eq(got, want, label)
  checks = checks + 1
  if got ~= want then
    failures[#failures + 1] = label .. ": got " .. tostring(got) .. ", want " .. tostring(want)
  end
end

local priorities = {"head", "torso", "right arm", "left arm", "right leg", "left leg"}
local function new_world(class)
  local w = world.new({class = class or "Runewarden"})
  local s = w.svo
  s.conf.parry, s.conf.guarding = true, false
  s.conf.keepup, s.sys.deffing = false, false
  s.sys.enabledgmcp = true
  s.me.wielded = {sword = {name = "a longsword"}}
  s.me.unparryables = {}
  -- Ignore unrelated housekeeping through the native ignore mechanism, not
  -- by replacing the action dictionary or its admission/dispatch functions.
  for name in pairs(s.dict_balanceless) do
    if name ~= "doparry" then s.ignore[name] = true end
  end
  for _, limb in ipairs(priorities) do s.sp.nextprio(limb) end
  s.sp.setparry("full")
  w.advance(0)
  w.sent = {}
  return w
end

local function desired(w)
  local selected = {}
  for limb, value in pairs(w.svo.sp_config.parry_shouldbe) do
    if value then selected[#selected + 1] = limb end
  end
  table.sort(selected)
  return table.concat(selected, ", ")
end

local function dispatch(w)
  w.svo.check_balanceless_acts()
  w.advance(0) -- native send batching runs on a zero timer
  return table.concat(w.sent, " | ")
end

local function expect_parry(w, limb, label, verb)
  local s, action = w.svo, w.svo.dict.doparry.physical
  s.sp_checksp()
  eq(desired(w), limb, label .. ": public desired limb")
  eq(action.isadvisable(), true, label .. ": native admission")
  eq(dispatch(w), (verb or "parry") .. " " .. limb, label .. ": native onstart command")
  eq(s.doingaction("doparry"), true, label .. ": native action owns command")
  action.oncompleted(limb)
  s.killaction(action)
  eq(s.sys.sp_satisfied, true, label .. ": completion satisfies same config")
  eq(action.isadvisable(), false, label .. ": satisfied action not repeated")
  w.sent = {}
  eq(dispatch(w), "", label .. ": no repeat command")
end

-- Canonical native afflictions, not invented spaced keys. Each stage is
-- delivered through svo.addaff, so the actual dictionary owns native state.
for _, case in ipairs({
  {"mangledrightarm", "right arm"}, {"mutilatedrightarm", "right arm"},
  {"mangledleftarm", "left arm"}, {"mutilatedleftarm", "left arm"},
  {"mangledrightleg", "right leg"}, {"mutilatedrightleg", "right leg"},
  {"mangledleftleg", "left leg"}, {"mutilatedleftleg", "left leg"},
  {"mildconcussion", "head"}, {"seriousconcussion", "head"},
  {"mildtrauma", "torso"}, {"serioustrauma", "torso"},
}) do
  local w = new_world()
  eq(w.svo.sp_config.parry_actionlevel, nil, case[1] .. ": no unused threshold prerequisite")
  w.svo.addaff(case[1])
  expect_parry(w, case[2], case[1])
end

-- The game's stage names enter through svof's existing translation table;
-- the policy consumes that native state, rather than interpreting game
-- \"mangled\" as native mangled (which is only the damaged stage).
for _, case in ipairs({
  {"damagedleftarm", "mangledleftarm", "left arm"},
  {"mangledleftarm", "mutilatedleftarm", "left arm"},
  {"damagedrightleg", "mangledrightleg", "right leg"},
  {"mangledrightleg", "mutilatedrightleg", "right leg"},
  {"damagedhead", "mildconcussion", "head"},
  {"mangledhead", "seriousconcussion", "head"},
}) do
  local w = new_world()
  local native = w.svo.dict.sstosvoa[case[1]]
  eq(native, case[2], case[1] .. ": dictionary translation")
  w.svo.addaff(native)
  expect_parry(w, case[3], case[1] .. ": game stage via native translation")
end

do
  local w = new_world()
  local s = w.svo
  s.addaff("mutilatedleftarm")
  expect_parry(w, "left arm", "mangled arm before first restoration")
  s.dict.curingmutilatedleftarm.waitingfor.oncompleted()
  eq(s.affs.mutilatedleftarm, nil, "first restoration removes native mutilated")
  eq(s.affs.mangledleftarm ~= nil, true, "first restoration leaves native mangled")
  s.sp_checksp()
  eq(desired(w), "left arm", "first restoration still protects damaged arm")
  eq(dispatch(w), "", "already parrying degraded stage needs no repeat")
  s.dict.curingmangledleftarm.waitingfor.oncompleted()
  eq(s.affs.mangledleftarm, nil, "second restoration removes native mangled")
  eq(s.affs.crippledleftarm ~= nil, true, "second restoration leaves mending-only break")
  expect_parry(w, "head", "mending-only stage returns to selected fallback")
end

-- Mending-only breaks do not change full's restoration-stage policy.
for _, aff in ipairs({"crippledleftarm", "crippledrightarm", "crippledleftleg", "crippledrightleg"}) do
  local w = new_world()
  w.svo.addaff(aff)
  expect_parry(w, "head", aff .. ": selected-priority fallback")
end

do
  local w = new_world()
  local s = w.svo
  s.addaff("mangledleftleg")
  s.addaff("mutilatedrightarm")
  expect_parry(w, "right arm", "first damaged limb in selected priority order")
  s.removeaff("mutilatedrightarm")
  expect_parry(w, "left leg", "cured priority yields to remaining damaged limb")
  s.removeaff("mangledleftleg")
  expect_parry(w, "head", "all restoration damage cured returns to selected fallback")
end

do
  local w = new_world()
  local s = w.svo
  s.sp.setup()
  for _, limb in ipairs({"left leg", "right leg", "left arm", "right arm", "torso", "head"}) do
    s.sp.nextprio(limb)
  end
  s.sp.setparry("full")
  eq(s.sps.settingup, nil, "setup completes without numeric action levels")
  expect_parry(w, "left leg", "user-selected fallback, not a hardcoded head")
end

-- Setup resets only the owned policy fields, preserving public identity,
-- nested references and unrelated user configuration. Old closures and the
-- dictionary's public-table consumer must still agree after setup/reload.
do
  local w = new_world()
  local s = w.svo
  local config, prios, wanted = s.sp_config, s.sp_config.priority, s.sp_config.parry_shouldbe
  local current = s.sps.parry_currently
  local old_check, old_manual = s.sp_checksp, s.sp_setparry
  local userdata = {private = "retain me"}
  config.userdata, config.morphskill = userdata, "hydra"
  current.torso = true
  s.sp.setup()
  eq(s.sp_config, config, "setup retains public config identity")
  eq(config.priority, prios, "setup retains priority table identity")
  eq(config.parry_shouldbe, wanted, "setup retains desired table identity")
  eq(config.userdata, userdata, "setup retains unrelated user data")
  eq(config.morphskill, "hydra", "setup retains unrelated morph setting")
  eq(#prios, 0, "setup clears previous priorities")
  eq(desired(w), "", "setup clears desired limbs")
  eq(s.sps.parry_currently, current, "setup retains actual parry table")
  eq(current.torso, true, "setup does not invent a change to actual parry")
  for _, limb in ipairs(priorities) do s.sp.nextprio(limb) end
  s.sp.setparry("manual")
  old_manual("la")
  old_check()
  expect_parry(w, "left arm", "pre-setup closure agrees with native executor")

  config.parry_actionlevel = {head = 275}
  s.sp.setparrylevel = function() error("obsolete reload API survived") end
  s.loader.parry()
  eq(s.sp_config, config, "reload retains public config identity")
  eq(config.priority, prios, "reload retains selected priority data")
  eq(config.parry_shouldbe, wanted, "reload retains desired table identity")
  eq(config.userdata, userdata, "reload retains unrelated user data")
  eq(s.sps.parry_currently, current, "reload retains current state identity")
  eq(current["left arm"], true, "reload retains confirmed current limb")
  eq(config.parry_actionlevel, nil, "reload drops obsolete action-level property")
  eq(s.sp.setparrylevel, nil, "reload drops obsolete action-level setter")
  old_manual("rl")
  old_check()
  expect_parry(w, "right leg", "pre-reload closure agrees with native executor")
end

-- Simulate Mudlet's table.load boundary; file loading must target the same
-- table already captured by policy/executor users, and legacy thresholds
-- must not return when reading an old configuration.
do
  local w = new_world()
  local s, config = w.svo, w.svo.sp_config
  local old_check = s.sp_checksp
  w.env.lfs.attributes = function(path) return path == "./svo/config/sp_config" end
  w.env.table.load = function(path, into)
    eq(path, "./svo/config/sp_config", "reload reads native config path")
    eq(into, config, "saved config loads into existing public table")
    into.parry = "lasthit"
    into.parry_actionlevel = {head = 275}
  end
  s.loader.parry()
  eq(s.sp_config, config, "saved configuration does not replace public table")
  eq(config.parry_actionlevel, nil, "saved legacy threshold removed")
  s.me.lasthitlimb = "left leg"
  old_check()
  expect_parry(w, "left leg", "saved strategy visible to pre-reload closure and executor")
end

for _, case in ipairs({
  {"lasthit", "left arm", "left arm"},
  {"lasthit opposite limb", "left arm", "right arm"},
  {"lasthit opposite limb", "head", "torso"},
  {"lasthit opposite side", "left arm", "left leg"},
  {"lasthit opposite side", "right leg", "right arm"},
  {"lasthit opposite side", "torso", "head"},
}) do
  local w = new_world()
  w.svo.me.lasthitlimb = case[2]
  w.svo.sp.setparry(case[1])
  expect_parry(w, case[3], case[1] .. " from " .. case[2])
end

do
  local w = new_world()
  local s = w.svo
  s.sp.setparry("manual")
  s.sp_setparry("ra")
  expect_parry(w, "right arm", "manual policy")
  s.sp_setparry("n")
  eq(desired(w), "", "manual nothing does not use fallback")
  eq(s.dict.doparry.physical.isadvisable(), true, "manual unparry admitted")
  eq(dispatch(w), "parry nothing", "native manual unparry command")
end

do
  local w = new_world()
  local s = w.svo
  local policy = function()
    for limb in pairs(s.sp_config.parry_shouldbe) do
      s.sp_config.parry_shouldbe[limb] = limb == "torso"
    end
  end
  s.sp_config.parry = policy
  s.loader.parry()
  eq(s.sp_config.parry, policy, "reload retains custom function")
  expect_parry(w, "torso", "custom policy")
end

-- Exercise the real scheduler as well as dictionary admission: a desired
-- limb cannot bypass native hindering, weapon, capability or action gates.
for _, case in ipairs({
  {"parry disabled", function(s) s.conf.parry = false end},
  {"blocked parry", function(s) s.sys.blockparry = true end},
  {"paralysis", function(s) s.addaff("paralysis") end},
  {"GMCP empty hands", function(s) s.me.wielded = {} end},
  {"GMCP unparryable wield", function(s) s.me.unparryables["a longsword"] = true end},
  {"existing parry action", function(s) s.checkaction(s.dict.doparry.physical, true) end},
  {"balanceful physical action", function(s) s.checkaction(s.dict.diag.physical, true) end},
  {"balanceful defence action", function(s) s.checkaction(s.dict.mindseye.physical, true) end},
}) do
  local w = new_world()
  local s = w.svo
  s.addaff("mangledleftleg")
  s.sp_checksp()
  case[2](s)
  eq(desired(w), "left leg", case[1] .. ": desired limb retained")
  eq(s.dict.doparry.physical.isadvisable(), false, case[1] .. ": native admission blocked")
  eq(dispatch(w), "", case[1] .. ": native scheduler sends nothing")
end

for _, case in ipairs({
  {"stun", function(s) s.addaff("stun") end},
  {"sleep", function(s) s.addaff("sleep") end},
  {"balance", function(s) s.bals.balance = false end},
  {"equilibrium", function(s) s.bals.equilibrium = false end},
  {"left arm balance", function(s) s.bals.leftarm = false end},
  {"right arm balance", function(s) s.bals.rightarm = false end},
}) do
  local w = new_world()
  w.svo.addaff("mangledleftleg")
  w.svo.sp_checksp()
  case[2](w.svo)
  eq(dispatch(w), "", case[1] .. ": outer native scheduler blocks execution")
end

for _, case in ipairs({
  {"Runewarden", false, false, "parry"},
  {"Blademaster", true, false, "parry"},
  {"Monk", true, false, "guard"},
  {"Runewarden", true, true, "clawparry"},
  {"Monk", true, true, "clawparry"},
}) do
  local w = new_world(case[1])
  local s = w.svo
  if case[2] then s.me.wielded = {} else s.sys.enabledgmcp = false end
  s.defc.dragonform = case[3]
  if case[1] == "Monk" then s.conf.parry, s.conf.guarding = false, true end
  s.addaff("mangledleftleg")
  expect_parry(w, "left leg", case[1] .. ": native weapon/guard/dragon exception", case[4])
end

do
  local w = new_world("Monk")
  w.svo.conf.parry, w.svo.conf.guarding = false, false
  w.svo.addaff("mangledleftleg")
  w.svo.sp_checksp()
  eq(w.svo.dict.doparry.physical.isadvisable(), false, "guard disabled is not parry capability")
  eq(dispatch(w), "", "guard disabled sends nothing")
end

if #failures > 0 then
  for _, failure in ipairs(failures) do print("FAIL " .. failure) end
  error(string.format("%d/%d checks failed", #failures, checks))
end
print(string.format("ALL PASS (%d checks)", checks))
