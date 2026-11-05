-- Native warning ownership across checkstun's real copied paragraph replay.
-- Run from Sources/svof: lua tools/test_warning_replay.lua
-- Only Mudlet I/O is stubbed. Exact lines dispatch through the shipped catalog;
-- no manual deepcopy, checkstun bypass, or synthetic completion is used.
local world = dofile("tools/svof_world.lua")
local catalog = dofile("src/resources/trigger_catalog.lua")
local checks = 0
local function check(value, label)
  checks = checks + 1
  assert(value, label)
end
local function count(w, needle)
  local text, n, at = table.concat(w.echoes, ""), 0, 1
  while true do
    local found = text:find(needle, at, true)
    if not found then return n end
    n, at = n + 1, found + #needle
  end
end
local onset = "An off-duty prison guard pivots quickly and smashes the haft of his spear into the side of your head, making your ears ring."
local refusal = "You are too stunned to be able to do anything."
local recovery = "You are no longer stunned."
local negative = "What do you want to eat?"
local controller = "src/scripts/svo (curing skeleton, controllers, action system)/Controllers.lua"
local function feed(w, text)
  w.line(text)
  w.env.matches = {text}
  local dispatched = 0
  for _, folder in ipairs(catalog) do
    for i = 2, #folder do
      local trigger = folder[i]
      for j = 2, #trigger do
        if trigger[j][1] == "exact" and trigger[j][2] == text then
          local path = "src/triggers/" .. folder[1]:gsub(" / ", "/") .. "/"
            .. trigger[1]:gsub(" ", "_") .. ".lua"
          w.run(world.read_file(path), path)
          dispatched = dispatched + 1
          break
        end
      end
    end
  end
  check(dispatched > 0, "real catalog dispatch: " .. text)
end
local function prompt(w)
  w.prompt()
  w.advance(0)
  for _, link in ipairs(w.links) do
    check(not link:find("(e!)", 1, true), "native handler error: " .. link)
  end
end
local function fresh(balanced)
  local w = world.new({class="Runewarden", paused=false})
  w.svo.logging_in = false
  w.svo.conf.aillusion, w.svo.conf.batch = true, true
  w.svo.bals.balance, w.svo.bals.equilibrium = balanced, balanced
  w.advance(0)
  w.echoes, w.links, w.sent = {}, {}, {}
  return w
end
local function warnings(w, names)
  w.line("A warning observation follows.")
  for _, name in ipairs(names) do w.svo.givewarning({initialmsg=name}) end
end
local function park(w, names)
  feed(w, onset)
  warnings(w, names)
  prompt(w)
  check(w.svo.affs.stun == nil, "short paragraph waits for real stun confirmation")
  check(w.svo.affsp.stun == true, "short paragraph records native suspicion")
  check(w.svo.actions.checkstun_misc ~= nil, "unpaused curing starts native probe")
  check(w.svo.dict.checkstun.templifevision ~= nil, "native consumer parks paragraph")
  check(w.svo.dict.checkstun.tempactions ~= nil, "native consumer parks actions")
  for _, name in ipairs(names) do check(count(w, name) == 0, name .. ": not rendered while parked") end
end
local function resolve(w, text)
  feed(w, text)
  prompt(w)
  prompt(w)
  check(w.svo.dict.checkstun.templifevision == nil, "native paragraph snapshot released")
  check(w.svo.dict.checkstun.tempactions == nil, "native action snapshot released")
end
local function fresh_warning(w, marker)
  warnings(w, {marker})
  prompt(w)
  prompt(w)
  check(count(w, marker) == 1, marker .. ": fresh accepted warning once")
end

for _, balanced in ipairs({true, false}) do
  -- Both confirmation and recovery restore separately deep-copied lifevision
  -- and actions through checkstun, not through a test-constructed snapshot.
  for _, answer in ipairs({refusal, recovery}) do
    local w = fresh(balanced)
    park(w, {"REPLAY_FIRST", "REPLAY_SECOND"})
    resolve(w, answer)
    check((w.svo.affs.stun ~= nil) == (answer == refusal), "native confirmation/recovery state")
    check(count(w, "REPLAY_FIRST") == 1, "first copied warning accepted exactly once")
    check(count(w, "REPLAY_SECOND") == 1, "second copied warning accepted exactly once")
    local text = table.concat(w.echoes, "")
    check(text:find("REPLAY_FIRST", 1, true) < text:find("REPLAY_SECOND", 1, true), "copied batch preserves accepted order")
    prompt(w)
    check(count(w, "REPLAY_FIRST") == 1, "no copied warning replay on later prompt")
    fresh_warning(w, "AFTER_REPLAY")
  end

  -- A successful probe answer rejects the stun suspicion and its parked
  -- paragraph through the real missing-herb handler's onclear path.
  do
    local w = fresh(balanced)
    park(w, {"NEGATIVE_PROBE_WARNING"})
    resolve(w, negative)
    check(w.svo.affs.stun == nil and w.svo.affsp.stun == nil, "negative probe rejects stun")
    check(count(w, "NEGATIVE_PROBE_WARNING") == 0, "negative probe discards parked warning")
    fresh_warning(w, "AFTER_NEGATIVE_PROBE")
    feed(w, refusal)
    prompt(w)
    check(count(w, "NEGATIVE_PROBE_WARNING") == 0, "later real stun cannot revive rejected warning")
  end

  -- Explicit AI rejection must not leak a batch into the next accepted one.
  do
    local w = fresh(balanced)
    feed(w, onset)
    warnings(w, {"ILLUSION_WARNING"})
    w.svo.sys.flawedillusion = true
    prompt(w)
    check(w.svo.dict.checkstun.templifevision == false or w.svo.dict.checkstun.templifevision == nil, "rejected onset parks no paragraph")
    check(count(w, "ILLUSION_WARNING") == 0, "rejected paragraph silent")
    fresh_warning(w, "AFTER_ILLUSION")
    check(count(w, "ILLUSION_WARNING") == 0, "rejected paragraph contributes no stale warning")
  end

  -- A replacement warning action cannot inherit or later resurrect the old
  -- parked claim, even when native replay restores the old action over it.
  do
    local w = fresh(balanced)
    park(w, {"REPLACED_WARNING"})
    fresh_warning(w, "REPLACEMENT_WARNING")
    resolve(w, refusal)
    check(count(w, "REPLACED_WARNING") == 0, "restored superseded action cannot donate old claim")
    check(count(w, "REPLACEMENT_WARNING") == 1, "replacement does not replay")
    fresh_warning(w, "AFTER_REPLACEMENT_REPLAY")
  end
end

-- Native doaction owns timed expiry. Its warning timeout must invalidate a
-- parked claim even though checkstun removed the live warning action already.
do
  local w = fresh(true)
  local timed = {}
  for key, value in pairs(w.svo.dict.givewarning.happened) do timed[key] = value end
  timed.onstart = function() end
  -- Use the action system's normal wait input to expire this observational
  -- action before the separate stun probe; do not invoke the timeout callback.
  timed.customwait = .05 - w.svo.sys.wait - w.svo.syncdelay()
  w.svo.doaction(timed)
  park(w, {"EXPIRED_PARKED_WARNING"})
  w.advance(.06)
  check(w.svo.dict.checkstun.templifevision ~= nil, "expired claim remains in native parked snapshot")
  check(w.svo.actions.checkstun_misc ~= nil, "warning expires before native probe")
  resolve(w, refusal)
  check(count(w, "EXPIRED_PARKED_WARNING") == 0, "expired parked warning never renders")
  fresh_warning(w, "AFTER_PARKED_EXPIRY")
end

-- Session invalidation must reach parked snapshots, not merely lifevision.l.
for _, boundary in ipairs({"reload", "disconnect", "relogin"}) do
  local w = fresh(true)
  park(w, {"OLD_SESSION_WARNING"})
  if boundary == "reload" then
    w.run(world.read_file(controller), controller)
    w.svo.loader.controllers()
  elseif boundary == "disconnect" then
    for _, handler in ipairs(w.handlers) do
      if handler.name == "sysDisconnectionEvent" and not handler.killed then handler.f() end
    end
  else
    w.svo.signals.relogin:emit()
  end
  check(w.svo.dict.checkstun.templifevision ~= nil, boundary .. ": native snapshot still exercises epoch guard")
  resolve(w, refusal)
  check(count(w, "OLD_SESSION_WARNING") == 0, boundary .. ": old parked claim cannot render")
  fresh_warning(w, "NEW_SESSION_WARNING")
  check(count(w, "OLD_SESSION_WARNING") == 0, boundary .. ": no donation to new session")
end

-- A disconnected callback queued before reload cannot invalidate the new
-- owner's accepted paragraph after Mudlet has retired that handler.
do
  local w = fresh(true)
  local stale = w.handlers[w.svo.cnrl.warningdisconnecthandler].f
  w.run(world.read_file(controller), controller)
  w.svo.loader.controllers()
  park(w, {"CURRENT_OWNER_WARNING"})
  stale()
  resolve(w, refusal)
  check(count(w, "CURRENT_OWNER_WARNING") == 1, "retired disconnect callback has no authority")
end

print("ALL PASS: native warning replay (" .. checks .. " checks)")
