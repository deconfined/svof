-- Passive PRIOAFF observations through real native loaders and shipped scripts.
-- Run from Sources/svof: lua tools/test_priority_feedback.lua
-- Metadata matching is exercised separately by test_passive_observations.py;
-- this suite supplies explicit captures, including deliberately stale captures.
local world = dofile("tools/svof_world.lua")
local checks = 0
local function eq(actual, expected, label)
  checks = checks + 1
  assert(actual == expected, (label or "value")..": expected "..tostring(expected)..", got "..tostring(actual))
end
local ROOT = "src/scripts/"
local SERVER = ROOT.."svo (custom prompt, serverside)/Serverside.lua"
local SK = ROOT.."svo (curing skeleton, controllers, action system)/Curing_skeleton.lua"
local TRIGGERS = "src/triggers/svo (aliases, triggers)/svo/General/Server-side commands/"
local function eventcount(w, name)
  local n = 0
  for _, event in ipairs(w.events) do if event.name == name then n = n + 1 end end
  return n
end
local function serialize(value)
  if type(value) ~= "table" then return type(value)..":"..tostring(value) end
  local entries = {}
  for k, v in pairs(value) do entries[#entries+1] = serialize(k).."="..serialize(v) end
  table.sort(entries)
  return "{"..table.concat(entries, ";").."}"
end
local function ranks(s)
  local result = {}
  for action, balances in pairs(s.dict) do
    if type(balances) == "table" then
      for balance, data in pairs(balances) do
        if type(data) == "table" and (data.aspriority ~= nil or data.spriority ~= nil) then
          result[action.."/"..balance] = {data.aspriority, data.spriority}
        end
      end
    end
  end
  return serialize(result)
end
local function authority(s)
  return serialize({ranks = ranks(s), cache = s.sk.priochangecache,
    snapshot = s.sk.priosbeforechange, writer = s.sk.prioritywriter,
    serverignore = s.serverignore, sendqueue = s.sk.sendqueue,
    sendqueuel = s.sk.sendqueuel, sendcuringtimer = s.sk.sendcuringtimer,
    priochangetimer = s.sk.priochangetimer, priorityneedsync = s.sk.priorityneedsync})
end
local function fixture()
  local w = world.new({class = "Runewarden"})
  local s, e = w.svo, w.env
  s.logging_in, s.sk.logged_in = false, true
  s.conf.serverside = true
  s.setup_default_serverignore()
  s.sk.cancelpriorityupdates()
  s.sk.cancelprioritydelivery()
  s.sk.priorityneedsync = nil
  s.sk.priosbeforechange = s.sk.getbeforestateprios()
  w.advance(0)
  w.sent, w.events = {}, {}

  -- Faithfully dispatch both shipped static events and actual anonymous native
  -- lifecycle handlers; the world deliberately records but does not dispatch.
  local metadata = world.read_file(ROOT.."svo (core)/Event handlers/scripts.json")
  local registered = {}
  for name in assert(metadata:match('"eventHandlerList"%s*:%s*%[(.-)%]')):gmatch('"([^"]+)"') do
    registered[name] = true
  end
  w.run(world.read_file(ROOT.."svo (core)/Event handlers/svo_events.lua"), "static event bridge")
  local record = e.raiseEvent
  e.raiseEvent = function(name, ...)
    record(name, ...)
    if name == "svo priority aff changed" then
      local status, affliction, reason = ...
      eq(s.me.priorityaff.status, status, "event sees consistent status")
      eq(s.me.priorityaff.affliction, affliction, "event sees consistent raw affliction")
      eq(s.me.priorityaff.reason, reason, "event sees consistent reason")
    end
    if registered[name] then e.svo_events(name, ...) end
    for _, handler in ipairs(w.handlers) do
      if handler.name == name and not handler.killed then handler.f(name, ...) end
    end
  end
  return w
end
local function trigger(w, name, captures)
  if captures then w.env.matches = captures end
  w.run(world.read_file(TRIGGERS..name..".lua"), name)
end
local function observe(w, name, raw, status, affliction, reason)
  local before = authority(w.svo)
  local commands = #w.sent
  local timers = serialize(w.timers)
  local rankevents = eventcount(w, "svo prio changed")
  trigger(w, name, {"feedback", raw})
  local p = w.svo.me.priorityaff
  eq(p.status, status, name.." status")
  eq(p.affliction, affliction, name.." raw affliction")
  eq(p.reason, reason, name.." reason")
  eq(authority(w.svo), before, name.." leaves ranks/caches/packets untouched")
  eq(eventcount(w, "svo prio changed"), rankevents, name.." emits no rank event")
  eq(#w.sent, commands, name.." sends nothing")
  eq(serialize(w.timers), timers, name.." schedules no automatic query or command")
end

-- Startup is uncertainty, not an invented acknowledgement of absence.
do
  local w = fixture()
  local p = w.svo.me.priorityaff
  eq(p.status, "unknown", "startup unknown")
  eq(p.reason, "startup", "startup reason")
  eq(p.affliction, nil, "startup has no raw affliction")
  observe(w, "Priority_aff_clear", "asthma", "unknown", nil, "clear-unknown")
  eq(p.cleared, "asthma", "unknown clear retains named evidence")
  eq(p.mismatch, nil, "unknown clear invents no mismatch")
  local n = eventcount(w, "svo priority aff changed")
  observe(w, "Priority_aff_clear", "asthma", "unknown", nil, "clear-unknown")
  eq(eventcount(w, "svo priority aff changed"), n, "duplicate unknown clear is silent")

  observe(w, "Priority_aff_set", "asthma", "active", "asthma", "set")
  n = eventcount(w, "svo priority aff changed")
  observe(w, "Priority_aff_set", "asthma", "active", "asthma", "set")
  eq(eventcount(w, "svo priority aff changed"), n, "duplicate set is silent")
  observe(w, "Priority_aff_set", "weariness", "active", "weariness", "set")
  eq(p.affliction, "weariness", "game name is not replaced by native weakness")
  observe(w, "Priority_aff_set", "new unfamiliar affliction", "active", "new unfamiliar affliction", "set")
  eq(w.svo.dict["new unfamiliar affliction"], nil, "unknown name is not a native dictionary entry")
  observe(w, "Priority_aff_clear", "asthma", "unknown", nil, "clear-mismatch")
  eq(p.cleared, "asthma", "mismatch retains cleared name")
  eq(p.mismatch, true, "mismatch is explicit")
  eq(p.previous_affliction, "new unfamiliar affliction", "mismatch retains contradicted observation")
  n = eventcount(w, "svo priority aff changed")
  observe(w, "Priority_aff_clear", "asthma", "unknown", nil, "clear-mismatch")
  eq(eventcount(w, "svo priority aff changed"), n, "duplicate mismatch is silent")
  observe(w, "Priority_aff_clear", "weariness", "unknown", nil, "clear-unknown")
  eq(p.cleared, "weariness", "new unknown clear replaces evidence without claiming none")

  observe(w, "Priority_aff_set", "asthma", "active", "asthma", "set")
  observe(w, "Priority_aff_clear", "asthma", "none", nil, "clear")
  eq(p.cleared, "asthma", "matching clear retains named evidence")
  n = eventcount(w, "svo priority aff changed")
  observe(w, "Priority_aff_clear", "asthma", "none", nil, "clear")
  eq(eventcount(w, "svo priority aff changed"), n, "duplicate matching clear is silent")
  observe(w, "Priority_aff_clear", "weariness", "none", nil, "clear")
  eq(p.cleared, "weariness", "already-none clear remains none")

  observe(w, "Priority_aff_set", "asthma", "active", "asthma", "set")
  local before, sent = authority(w.svo), #w.sent
  w.env.matches = {"old unrelated feedback", "stale affliction", "stale actor"}
  trigger(w, "Priority_aff_none")
  eq(p.status, "none", "captureless feedback proves none")
  eq(p.reason, "none", "captureless feedback reason")
  eq(p.affliction, nil, "captureless feedback never reuses old affliction")
  eq(p.cleared, nil, "captureless feedback invents no named clear")
  eq(p.mismatch, nil, "captureless feedback clears stale mismatch")
  eq(p.previous_affliction, nil, "captureless feedback clears stale prior evidence")
  eq(authority(w.svo), before, "captureless feedback leaves native authority untouched")
  eq(#w.sent, sent, "captureless feedback sends nothing")
  n = eventcount(w, "svo priority aff changed")
  trigger(w, "Priority_aff_none")
  eq(eventcount(w, "svo priority aff changed"), n, "duplicate absence is silent")
  w.svo.onprompt(); w.advance(0)
  eq(p.status, "none", "full native prompt preserves observed absence")
  eq(#w.sent, sent, "native prompt emits no observation query or cure")
end

-- Set acknowledgements are observations, not native intent or per-set caches.
do
  local w = fixture()
  local s, p = w.svo, w.svo.me.priorityaff
  observe(w, "Priority_aff_set", "asthma", "active", "asthma", "set")
  observe(w, "Observed_curing_set", "external set", "unknown", nil, "curingset-switch")
  eq(p.curingset, "external set", "arbitrary raw set name is observable")
  eq(p.previous_affliction, "asthma", "switch retains previous observation as history only")
  local n = eventcount(w, "svo priority aff changed")
  observe(w, "Observed_curing_set", "external set", "unknown", nil, "curingset-switch")
  eq(eventcount(w, "svo priority aff changed"), n, "duplicate switch is silent")
  observe(w, "Priority_aff_set", "weariness", "active", "weariness", "set")
  observe(w, "Observed_curing_set", "normal", "unknown", nil, "curingset-switch")
  eq(p.curingset, "normal", "normal acknowledgement recorded")
  observe(w, "Observed_curing_set", "external set", "unknown", nil, "curingset-switch")
  eq(p.affliction, nil, "returning to set cannot restore remembered override")
  observe(w, "Priority_aff_none", nil, "none", nil, "none")
  observe(w, "Observed_curing_set", "slowcuring", "unknown", nil, "curingset-switch")
  eq(p.status, "unknown", "switch invalidates absence as well as active")

  -- Deliberate outgoing native commands and rank changes do not acknowledge
  -- either PRIOAFF or an active game set. These sends are user/native authority.
  observe(w, "Priority_aff_set", "asthma", "active", "asthma", "set")
  local observed = serialize(p)
  s.sendcuring("prioaff weariness")
  s.sendcuring("priority reset")
  s.sendc("curingset switch normal")
  eq(serialize(p), observed, "outgoing commands do not alter observations")
  s.prio.insert("asthma", "herb", 10000)
  eq(serialize(p), observed, "stored-priority change does not alter observation")
  s.sk.cancelpriorityupdates()
  s.addaff("asthma"); s.removeaff("asthma")
  eq(serialize(p), observed, "local affliction removal does not clear game override")
  s.serverignore.asthma = not s.serverignore.asthma
  eq(serialize(p), observed, "serverignore does not alter observation")
  s.conf.serverside = false
  s.signals.sync:emit()
  eq(serialize(p), observed, "native mode intent alone is not acknowledgement")
end

-- Preserve normal and slowcuring gag behavior without duplicate trigger paths.
for _, serverside in ipairs({false, true}) do
  for _, gag in ipairs({false, true}) do
    for _, slow in ipairs({false, true}) do
      local w = fixture()
      local s = w.svo
      if slow then s.addaff("aeon") end
      s.sk.cancelpriorityupdates(); s.sk.priorityneedsync = nil
      w.advance(0); w.sent = {}
      s.conf.serverside, s.conf.gagserverside = serverside, gag
      local deleted = 0
      s.deleteLineP = function() deleted = deleted + 1 end
      trigger(w, "Observed_curing_set", {"normal acknowledgement", "normal"})
      eq(deleted, serverside and gag and 1 or 0, "normal gag is unchanged")
      deleted = 0
      trigger(w, "Observed_curing_set", {"slow acknowledgement", "slowcuring"})
      eq(deleted, not slow and gag and 1 or 0, "slowcuring gag is unchanged")
      deleted = 0
      trigger(w, "Observed_curing_set", {"external acknowledgement", "external"})
      eq(deleted, 0, "new arbitrary-set observations do not invent gag behavior")
      eq(#w.sent, 0, "gag integration sends nothing")
    end
  end
end

-- Actual native connection/disconnection handlers remain authoritative; observer
-- handlers are independently owned, replaced once, and reject stale callbacks.
do
  local w = fixture()
  local s, e, p = w.svo, w.env, w.svo.me.priorityaff
  local nativeconnect, nativedisconnect = s.sk.priorityconnecthandler, s.sk.prioritydisconnecthandler
  local staleconnect = w.handlers[s.sk.priorityaffconnecthandler].f
  local staledisconnect = w.handlers[s.sk.priorityaffdisconnecthandler].f
  observe(w, "Priority_aff_set", "asthma", "active", "asthma", "set")
  s.conf.serverside = false -- prevent unrelated native reload resynchronization
  local sent = #w.sent
  w.run(world.read_file(SERVER), SERVER)
  eq(s.me.priorityaff, p, "reload preserves public record identity")
  eq(p.status, "unknown", "reload invalidates current certainty")
  eq(p.reason, "reload", "reload reason")
  eq(s.sk.priorityconnecthandler, nativeconnect, "reload preserves native connection handler")
  eq(s.sk.prioritydisconnecthandler, nativedisconnect, "reload preserves native disconnection handler")
  eq(#w.sent, sent, "reload observation emits no commands")
  local function livehandlers(name)
    local n = 0
    for _, handler in ipairs(w.handlers) do
      if handler.name == name and not handler.killed then n = n + 1 end
    end
    return n
  end
  local connects, disconnects = livehandlers("sysConnectionEvent"), livehandlers("sysDisconnectionEvent")
  w.run(world.read_file(SERVER), SERVER)
  eq(livehandlers("sysConnectionEvent"), connects, "reload does not accumulate connection handlers")
  eq(livehandlers("sysDisconnectionEvent"), disconnects, "reload does not accumulate disconnection handlers")
  observe(w, "Priority_aff_set", "weariness", "active", "weariness", "set")
  local n = eventcount(w, "svo priority aff changed")
  staleconnect(); staledisconnect()
  eq(p.status, "active", "replaced callbacks cannot invalidate fresh observation")
  eq(eventcount(w, "svo priority aff changed"), n, "replaced callbacks emit no events")
  e.raiseEvent("sysDisconnectionEvent")
  eq(p.status, "unknown", "native disconnect invalidates observed override")
  eq(p.reason, "disconnect", "native disconnect reason")
  eq(p.curingset, nil, "disconnect drops observed set certainty")
  eq(s.sk.prioritydisconnected, true, "native priority disconnect handler still runs")
  eq(eventcount(w, "svo priority aff changed"), n + 1, "disconnect emits one observation event")
  e.raiseEvent("sysConnectionEvent")
  eq(p.status, "unknown", "native reconnect does not restore old override")
  eq(p.reason, "reconnect", "native reconnect reason")
  eq(s.sk.prioritydisconnected, nil, "native priority connection handler still runs")
  eq(s.logging_in, true, "native login gate still runs")
  eq(#w.sent, sent, "connection observations issue no queries or commands")
  observe(w, "Priority_aff_none", nil, "none", nil, "none")
  w.run(world.read_file(SK), SK)
  w.run(world.read_file(SERVER), SERVER)
  eq(s.me.priorityaff, p, "whole native reload retains owned record")
  eq(p.status, "unknown", "whole native reload invalidates explicit absence")
  eq(p.reason, "reload", "whole native reload reason")
  eq(livehandlers("sysConnectionEvent"), connects, "whole reload has one owned connection family")
  eq(livehandlers("sysDisconnectionEvent"), disconnects, "whole reload has one owned disconnect family")
end

print("priority feedback: "..checks.." checks passed")
