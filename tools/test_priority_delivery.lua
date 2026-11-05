-- Real-source, deterministic priority-delivery consumer regressions.
-- Run from Sources/svof: lua tools/test_priority_delivery.lua
-- Mudlet transport/timers are stubbed by svof_world; the public priorities,
-- static event bridge, serverside snapshots and curing writer are real source.
local world = dofile("tools/svof_world.lua")
local checks = 0
local function eq(actual, expected, label)
  checks = checks + 1
  assert(actual == expected, (label or "value")..": expected "..tostring(expected)..", got "..tostring(actual))
end
local function ok(value, label) eq(not not value, true, label) end
local ROOT = "src/scripts/"
local SK = ROOT.."svo (curing skeleton, controllers, action system)/Curing_skeleton.lua"
local SERVER = ROOT.."svo (custom prompt, serverside)/Serverside.lua"

local function fixture()
  local w = world.new({class = "Runewarden"})
  local e, s = w.env, w.svo
  s.logging_in, s.sk.logged_in = false, true
  s.conf.serverside = true
  s.setup_default_serverignore()
  s.sk.cancelpriorityupdates()
  s.sk.cancelprioritydelivery()
  s.sk.priosbeforechange = s.sk.getbeforestateprios()
  s.sk.priochangecache = {special = {focustoggle = s.conf.focus}}
  s.sk.priorityneedsync = nil
  w.advance(0)
  w.sent = {}

  -- Load the shipped static bridge, and its actual registration list. The
  -- base world records raiseEvent but deliberately doesn't dispatch it.
  local metadata = world.read_file(ROOT.."svo (core)/Event handlers/scripts.json")
  local registered = {}
  for event in assert(metadata:match('"eventHandlerList"%s*:%s*%[(.-)%]')):gmatch('"([^"]+)"') do
    registered[event] = true
  end
  world.compile(world.read_file(ROOT.."svo (core)/Event handlers/svo_events.lua"), "static event bridge", e)()
  local record_event = e.raiseEvent
  e.raiseEvent = function(name, ...)
    record_event(name, ...)
    if registered[name] then e.svo_events(name, ...) end
    for _, handler in ipairs(w.handlers) do
      if handler.name == name and not handler.killed then handler.f(name, ...) end
    end
  end

  -- A small server-side consumer, not a second implementation of the writer:
  -- interpret actual emitted commands, remembering the selected curing set.
  local c = {active = "external", sets = {}, writes = {}, commands = {}, aliases = {}}
  local function getset(name)
    if not c.sets[name] then c.sets[name] = {affliction = {}, defence = {}} end
    return c.sets[name]
  end
  getset("external").affliction.asthma = "17"
  local consume
  consume = function(command)
    local alias, body = command:match("^setalias (%w+) (.*)$")
    if alias then c.aliases[alias] = body; return end
    if c.aliases[command] and command == "multicmd" then
      for part in c.aliases[command]:gmatch("[^/]+") do consume(part) end
      return
    end
    if command:match("^9multicmd ") then
      for part in command:gmatch("{([^}]*)}") do consume(part) end
      return
    end
    if command:find("/", 1, true) then
      for part in command:gmatch("[^/]+") do consume(part) end
      return
    end
    c.commands[#c.commands+1] = command
    local lower = command:lower()
    local set = lower:match("^curingset switch (.+)$")
    if set then c.active = set; getset(set); return end
    local arguments = lower:match("^curing priority (.+)$")
    if not arguments then return end
    ok(#command < s.sk.achaea_command_max_length, "native priority command fits limit")
    -- HELP lists this global regeneration setting separately from stored
    -- affliction/defence ranks; it remains on Svof's native buffered path.
    if arguments == "health" or arguments == "mana" then c.regeneration = arguments; return end
    local kind = "affliction"
    if arguments:match("^defence ") then kind = "defence"; arguments = arguments:sub(9) end
    local selected = getset(c.active)
    ok(c.active == "normal" or c.active == "slowcuring", "every stored priority write selects an owned set")
    if arguments == "reset" or arguments == "list reset" then
      selected[kind] = {}
      c.writes[#c.writes+1] = {set = c.active, kind = kind, reset = true}
      return
    end
    local tokens = {}
    for token in arguments:gmatch("%S+") do tokens[#tokens+1] = token end
    eq(#tokens % 2, 0, "rank command contains action/rank pairs")
    for i = 1, #tokens, 2 do
      if tokens[i+1] == "reset" then selected[kind][tokens[i]] = nil
      else selected[kind][tokens[i]] = tokens[i+1] end
      c.writes[#c.writes+1] = {set = c.active, kind = kind, action = tokens[i], rank = tokens[i+1]}
    end
  end
  local record_send = e.send
  e.send = function(command, echo)
    record_send(command, echo)
    consume(command)
  end
  e.sendAll = function(...)
    for _, command in ipairs({...}) do if type(command) == "string" then e.send(command, false) end end
  end
  w.consumer = c
  return w
end

local function finish(w)
  for _ = 1, 100 do
    w.advance(2)
    local owner = w.svo.sk.prioritywriter
    if not w.svo.sk.priochangetimer and not owner.timer and not owner.batch
        and not owner.snapshot and not owner.pending[owner.head] then return end
  end
  error("priority writer did not finish")
end
local function ranks(w, action, set)
  local result = {}
  for _, write in ipairs(w.consumer.writes) do
    if write.action == action and (not set or write.set == set) then result[#result+1] = write.rank end
  end
  return table.concat(result, ",")
end
local function exhaust(w)
  for i = 1, 5 do
    w.svo.sendcuringprio("paralysis "..i, "affliction")
    w.svo.sk.dosendprios()
  end
end
local function callback(w, id)
  return assert(w.timers[id], "expected an owned timer").f
end

-- Bound real wire fragmentation by payload and the existing command limit,
-- independently for each owned set/kind stream. Every full chunk must leave
-- less than one entry's room; arbitrary pairs(diff) order must not turn each
-- interleaved aff/def action into a separate throttled command.
local function packed_snapshot(w, first, label)
  local streams, active, total = {}, nil, 0
  for i = first or 1, #w.consumer.commands do
    local command = w.consumer.commands[i]:lower()
    active = command:match("^curingset switch (.+)$") or active
    local prefix, arguments = "curing priority", command:match("^curing priority (.+)$")
    if arguments and arguments:match("^defence ") then
      prefix, arguments = prefix.." defence", arguments:sub(9)
    end
    if arguments and arguments ~= "reset" and arguments ~= "list reset"
        and arguments ~= "health" and arguments ~= "mana" then
      local key = assert(active, "stored priority transaction selects a set")..":"..prefix
      local stream = streams[key] or {count = 0, bytes = 0, maxentry = 0, prefix = #prefix}
      streams[key] = stream
      stream.count, total = stream.count + 1, total + 1
      for action, rank in arguments:gmatch("(%S+)%s+(%S+)") do
        local length = 2 + #action + #rank
        stream.bytes = stream.bytes + length
        stream.maxentry = math.max(stream.maxentry, length)
      end
    end
  end
  ok(total > 0, label.." actually delivers native ranks")
  for key, stream in pairs(streams) do
    local capacity = w.svo.sk.achaea_command_max_length - stream.prefix - stream.maxentry
    ok(stream.count <= math.ceil(stream.bytes / capacity), label.." packs "..key.." without avoidable fragments")
  end
end

-- Empty drains do not send or create throttle-reset timers.
do
  local w = fixture()
  w.svo.sk.dosendprios(); w.svo.sk.dosendprios(); w.advance(2)
  eq(#w.sent, 0, "empty drains emit nothing")
  eq(w.svo.sk.prioritywriter.timer, nil, "empty drains leave no timer")
end

-- Normal writes are explicitly selected while in slow mode, even if the
-- user's active set was external. Aff/def ignores retain native syntax.
do
  local w = fixture(); local s, c = w.svo, w.consumer
  s.sys.sync = true
  s.sendcuringprio("asthma 3", "affliction")
  s.sendcuringprio("deafness reset", "defence")
  w.advance(0)
  eq(c.sets.normal.affliction.asthma, "3", "normal rank delivered in slow mode")
  eq(ranks(w, "deafness"), "reset", "normal defence ignore command delivered")
  eq(c.sets.normal.defence.deafness, nil, "normal defence upkeep removed")
  eq(c.active, "slowcuring", "normal writes restore actual slow mode")
  eq(c.sets.external.affliction.asthma, "17", "external set unchanged")
  s.sys.sync = false
  s.sendcuringprio("asthma 26", "affliction", true)
  s.sendcuringprio("blindness 4", "defence", true)
  w.advance(0)
  eq(c.sets.slowcuring.affliction.asthma, "26", "slow affliction ignore delivered")
  eq(c.sets.slowcuring.defence.blindness, "4", "slow defence rank delivered")
  eq(c.active, "normal", "slow writes restore normal mode")
end

-- A burst has one zero-timer drain; duplicate adjacent updates deliver once.
do
  local w = fixture(); local s = w.svo
  for _ = 1, 20 do s.sendcuringprio("asthma 3", "affliction") end
  local timer = s.sk.prioritywriter.timer
  ok(timer, "burst owns one timer")
  w.advance(0)
  eq(ranks(w, "asthma"), "3", "burst delivers once")
  eq(s.sk.prioritywriter.timer, nil, "delivered burst leaves no timer")
  -- Non-adjacent ranks are not silently dropped as duplicate old entries.
  s.sendcuringprio("asthma 4", "affliction")
  s.sendcuringprio("asthma 9", "affliction")
  s.sendcuringprio("asthma 4", "affliction")
  w.advance(0)
  eq(ranks(w, "asthma"), "3,4,9,4", "non-adjacent repeated rank retains ordering")
end

-- Actual native buffered cures flush before the selected-set transaction.
do
  local w = fixture()
  w.svo.sendc("eat magnesium", "smoke 123")
  w.svo.sendcuringprio("asthma 9", "affliction")
  w.svo.sk.dosendprios()
  eq(w.consumer.commands[1], "eat magnesium", "first buffered cure remains first")
  eq(w.consumer.commands[2], "smoke 123", "second buffered cure remains second")
  eq(w.consumer.commands[3], "curingset switch normal", "set transaction follows buffered native batch")
end

-- Reproduction: five public drains, delayed asthma 3, then newer asthma 9.
-- Explicit repeated drains and the zero timer must never overtake that FIFO.
do
  local w = fixture(); local s, c = w.svo, w.consumer
  exhaust(w)
  s.sendcuringprio("asthma 3", "affliction"); s.sk.dosendprios()
  local old = callback(w, s.sk.prioritywriter.timer)
  s.sendcuringprio("asthma 9", "affliction")
  s.sendcuringprio("paralysis 2", "affliction")
  s.sk.dosendprios(); w.advance(0)
  eq(ranks(w, "asthma"), "", "throttled writes don't bypass delay")
  s.sys.sync = true -- changed AFTER detaching the pending batches
  s.signals.sync:emit()
  w.advance(2)
  eq(ranks(w, "asthma"), "3,9", "older write cannot replay after newer write")
  eq(c.sets.normal.affliction.asthma, "9", "latest normal priority wins")
  eq(c.sets.normal.affliction.paralysis, "2", "new work is not cleared by old drain")
  eq(c.active, "slowcuring", "deferred drain restores mode at delivery, not enqueue")
  local count = #w.sent
  old()
  eq(#w.sent, count, "replaced throttle callback cannot replay")
end

do
  local w = fixture(); local s = w.svo
  s.sys.sync = true
  exhaust(w)
  s.sendcuringprio("blindness 4", "defence", true)
  s.sk.dosendprios()
  s.sys.sync = false
  s.signals.sync:emit()
  w.advance(2)
  eq(w.consumer.sets.slowcuring.defence.blindness, "4", "delayed slow defence retains its destination")
  eq(w.consumer.active, "normal", "delayed slow defence restores mode changed to normal")
end

-- Overflow is another detached FIFO producer, not a direct-send bypass.
do
  local w = fixture(); local s = w.svo
  exhaust(w)
  s.sk.achaea_command_max_length = 58
  for i = 1, 18 do s.sendcuringprio("asthma "..i, "affliction") end
  s.sendcuringprio("blindness reset", "defence")
  s.sendcuringprio("paralysis 26", "affliction", true)
  w.advance(0)
  eq(ranks(w, "asthma"), "", "overflow doesn't bypass occupied rate window")
  finish(w)
  local expected = {}
  for i = 1, 18 do expected[i] = tostring(i) end
  eq(ranks(w, "asthma"), table.concat(expected, ","), "all overflow ranks delivered in order")
  eq(w.consumer.sets.normal.affliction.asthma, "18", "overflow ends at latest rank")
  eq(ranks(w, "blindness"), "reset", "defence reset survives overflow")
  eq(w.consumer.sets.slowcuring.affliction.paralysis, "26", "slow ignore survives overflow")
end

-- A killed zero callback may not kill or consume the new live timer/batch.
do
  local w = fixture(); local s = w.svo
  s.sendcuringprio("asthma 3", "affliction")
  local stale = callback(w, s.sk.prioritywriter.timer)
  s.sk.dosendprios()
  s.sendcuringprio("asthma 9", "affliction")
  local live = s.sk.prioritywriter.timer
  stale()
  eq(s.sk.prioritywriter.timer, live, "old zero callback cannot erase new timer")
  eq(ranks(w, "asthma"), "3", "old zero callback cannot send new batch")
  w.advance(0)
  eq(ranks(w, "asthma"), "3,9", "new callback still delivers its own work")
end

-- Public prio.insert goes through the existing static event consumer, diff
-- snapshots, rank conversion, batching and selected-set writer end to end.
do
  local w = fixture(); local s = w.svo
  ok(s.prio.insert("asthma", "herb", 10000), "public normal insertion accepted")
  ok(s.prio.insert("asthma", "herb", 10001), "public burst insertion accepted")
  local timer = s.sk.priochangetimer
  ok(timer, "static bridge schedules real serverside diff")
  w.advance(0); finish(w)
  eq(w.consumer.sets.normal.affliction.asthma, "1", "public insertion reaches native rank one")
  eq(ranks(w, "asthma", "normal"), "1", "public burst produces one effective rank")
  s.sys.sync = false
  ok(s.prio.insert("asthma_herb", "slowcuring", 10000), "public slow insertion accepted")
  w.advance(0); finish(w)
  eq(w.consumer.sets.slowcuring.affliction.asthma, "1", "public slow insertion reaches slow native set")
  eq(w.consumer.active, "normal", "public slow insertion restores active normal set")
end

-- Initial native enable and an ordinary public edit during real GMCP aeon
-- use bounded, packed snapshots instead of alternating tiny aff/def batches.
do
  local w = fixture(); local s, e, c = w.svo, w.env, w.consumer
  s.conf.serverside = false
  s.tntf_set("serverside", "on", false)
  w.advance(0); finish(w)
  packed_snapshot(w, 1, "initial native enable")
  e.gmcp.Char.Afflictions.Add = {name = "aeon"}
  s.signals.gmcpcharafflictionsadd:emit()
  w.advance(0)
  eq(s.sys.sync, true, "GMCP aeon enters native slow mode")
  local first = #c.commands + 1
  ok(s.prio.insert("asthma", "herb", 10000), "normal edit accepted during GMCP aeon")
  w.advance(0); finish(w)
  packed_snapshot(w, first, "ordinary native snapshot")
  eq(c.sets.normal.affliction.asthma, "1", "normal edit arrives while native slow mode is active")
  eq(c.active, "slowcuring", "packed normal snapshot restores slow mode")
  eq(c.sets.external.affliction.asthma, "17", "packed snapshots preserve external set")
end

-- Coalescing independent snapshot streams never crosses an older detached
-- producer, a later snapshot, or an intervening whole-list reset.
do
  local w = fixture(); local s = w.svo
  exhaust(w)
  s.sendcuringprio("asthma 3", "affliction"); s.sk.dosendprios()
  s.sk.beginprioritysnapshot()
  for _, rank in ipairs({4, 9, 4}) do
    s.sendcuringprio("asthma "..rank, "affliction")
    s.sendcuringprio("blindness "..rank, "defence")
    s.sendcuringprio("asthma "..rank, "affliction", true)
  end
  s.sk.endprioritysnapshot()
  s.sk.beginprioritysnapshot()
  s.sendcuringprio("asthma 8", "affliction")
  s.sendcuringprio("reset", "affliction")
  s.sendcuringprio("asthma 2", "affliction")
  s.sk.endprioritysnapshot()
  finish(w)
  eq(ranks(w, "asthma", "normal"), "3,4,9,4,8,2", "snapshot ranks retain per-stream FIFO across detached work and reset")
  eq(ranks(w, "asthma", "slowcuring"), "4,9,4", "independent slow ranks retain producer order")
  eq(ranks(w, "blindness", "normal"), "4,9,4", "independent defence ranks retain producer order")
  eq(w.consumer.sets.normal.affliction.asthma, "2", "post-reset native rank remains final")
  local order = {}
  for _, write in ipairs(w.consumer.writes) do
    if write.set == "normal" and write.kind == "affliction" and (write.reset or write.action == "asthma") then
      order[#order+1] = write.reset and "reset" or write.rank
    end
  end
  eq(table.concat(order, ","), "3,4,9,4,8,reset,2", "whole-list reset is a consumer-visible snapshot barrier")
end

-- Overflow inside a coalesced native snapshot preserves each rank stream,
-- with the normal command-size limit still applying to every emitted chunk.
do
  local w = fixture(); local s = w.svo
  exhaust(w)
  s.sk.achaea_command_max_length = 58
  s.sk.beginprioritysnapshot()
  for rank = 1, 18 do
    s.sendcuringprio("asthma "..rank, "affliction")
    s.sendcuringprio("blindness "..rank, "defence")
    s.sendcuringprio("asthma "..rank, "affliction", true)
  end
  s.sk.endprioritysnapshot()
  finish(w)
  local expected = {}
  for rank = 1, 18 do expected[rank] = tostring(rank) end
  local ordered = table.concat(expected, ",")
  eq(ranks(w, "asthma", "normal"), ordered, "snapshot overflow retains normal affliction order")
  eq(ranks(w, "asthma", "slowcuring"), ordered, "snapshot overflow retains slow affliction order")
  eq(ranks(w, "blindness", "normal"), ordered, "snapshot overflow retains defence order")
end

-- Initial enable resets only owned sets, before rank writes. Manual reset
-- cancels detached old work and resets both aff/def lists in both owned sets.
do
  local w = fixture(); local s, c = w.svo, w.consumer
  s.conf.serverside, s.sys.sync = false, true
  s.conf.serverside = true
  w.env.raiseEvent("svo config changed", "serverside")
  w.advance(0); finish(w)
  eq(c.sets.external.affliction.asthma, "17", "initial PRIORITY RESET cannot touch external set")
  for _, set in ipairs({"normal", "slowcuring"}) do
    for _, kind in ipairs({"affliction", "defence"}) do
      local first
      for _, write in ipairs(c.writes) do if write.set == set and write.kind == kind then first = write; break end end
      ok(first and first.reset, "initial owned "..set.." "..kind.." reset precedes ranks")
    end
  end
  eq(c.active, "slowcuring", "initial enable preserves current intended slow mode")

  s.sk.cancelprioritydelivery(); exhaust(w)
  s.sendcuringprio("asthma 3", "affliction"); s.sk.dosendprios()
  local stale = callback(w, s.sk.prioritywriter.timer)
  local start = #c.writes
  s.sk.resetserversideprios()
  s.sendcuringprio("asthma 9", "affliction")
  stale(); w.advance(0); finish(w)
  local resetcount = 0
  for i = start+1, #c.writes do
    local write = c.writes[i]
    if write.reset then resetcount = resetcount+1 end
    ok(not (write.action == "asthma" and write.rank == "3"), "manual reset discards superseded detached batch")
  end
  eq(resetcount, 4, "manual reset owns all four lists")
  eq(c.sets.normal.affliction.asthma, "9", "rank after manual reset delivered last")
end

-- The public classchange path resets before reloading its native loaders.
-- Reload cancellation must not silently discard those class-defence resets.
do
  local w = fixture(); local s, c = w.svo, w.consumer
  s.sendcuringprio("asthma 9", "affliction")
  w.advance(0)
  local first = #c.writes + 1
  s.classchange("Magi")
  local resets = 0
  for i = first, #c.writes do if c.writes[i].reset then resets = resets + 1 end end
  eq(resets, 4, "classchange delivers all owned resets before loader cancellation")
  eq(c.sets.external.affliction.asthma, "17", "classchange reset preserves external set")
end

-- A public change has already advanced the producer cache and before-state,
-- but NONE of its wire ranks have drained. Each loader and both loader orders
-- must replace that discarded work with a fresh native snapshot.
for _, order in ipairs({{SK}, {SERVER}, {SK, SERVER}, {SERVER, SK}}) do
  for _, produced in ipairs({false, true}) do
    local w = fixture(); local s, c = w.svo, w.consumer
    exhaust(w)
    ok(s.prio.insert("asthma", "herb", 10000), "reload fixture public edit accepted")
    local staleupdate = callback(w, s.sk.priochangetimer)
    local stale
    if produced then
      s.sk.updateserversideprios()
      stale = callback(w, s.sk.prioritywriter.timer)
    end
    eq(ranks(w, "asthma"), "", "reload fixture native change remains unsent")
    for _, path in ipairs(order) do w.run(world.read_file(path), path) end
    local count = #w.sent
    staleupdate(); if stale then stale() end
    eq(#w.sent, count, "reload rejects old producer/writer callbacks before fresh timer")
    w.advance(0); finish(w)
    eq(c.sets.normal.affliction.asthma, "1", "native public change survives loader reload without another edit")
    eq(ranks(w, "asthma", "normal"), "1", "only current snapshot rank reaches consumer after reload")
    eq(c.sets.external.affliction.asthma, "17", "reload snapshot owns only native sets")
    local finalcount = #w.sent
    staleupdate(); if stale then stale() end
    eq(#w.sent, finalcount, "old callbacks remain inert after fresh snapshot delivery")
  end
end

-- Disable/disconnect own both timer families, including unsent snapshots
-- whose caches have already advanced. Offline reloads and new public edits
-- cannot send until enable/login; only a fresh native snapshot then resumes.
for _, boundary in ipairs({"disable", "disconnect"}) do
  local w = fixture(); local s, c = w.svo, w.consumer
  exhaust(w)
  ok(s.prio.insert("asthma", "herb", 10000), boundary.." queues public snapshot update")
  local staleupdate = callback(w, s.sk.priochangetimer)
  s.sk.updateserversideprios()
  local stale = callback(w, s.sk.prioritywriter.timer)
  local staleconnect = w.handlers[s.sk.priorityconnecthandler].f
  local staledisconnect = w.handlers[s.sk.prioritydisconnecthandler].f
  if boundary == "disable" then
    s.conf.serverside = false; w.env.raiseEvent("svo config changed", "serverside")
  else
    w.env.raiseEvent("sysDisconnectionEvent")
  end
  local count = #w.sent
  for _, path in ipairs({SK, SERVER}) do w.run(world.read_file(path), path) end
  stale(); staleupdate()
  staleconnect(); staledisconnect()
  ok(s.prio.insert("asthma", "herb", 10001), boundary.." admits an offline local priority change")
  s.sendcuringprio("asthma 19", "affliction")
  w.advance(4)
  eq(#w.sent, count, boundary.." and offline loader reloads cannot leak priority sends")
  if boundary == "disable" then
    s.conf.serverside = true; w.env.raiseEvent("svo config changed", "serverside")
  else
    w.env.raiseEvent("sysConnectionEvent")
    eq(s.logging_in, true, "native connection event gates delivery during login")
    eq(s.sk.prioritydisconnected, nil, "native connection event reopens the disconnected boundary")
    s.signals.gmcpcharname:emit()
    w.advance(0)
    eq(ranks(w, "asthma"), "", "login setup cannot drain priorities before native login completion")
    ok(w.line("Password correct. Welcome to Achaea.") > 0, "native welcome trigger completes login")
    eq(s.logging_in, false, "native welcome trigger releases the login gate")
  end
  w.advance(0); finish(w)
  eq(c.sets.normal.affliction.asthma, "1", boundary.." resumes latest native public priority without another edit")
  ok(not ranks(w, "asthma", "normal"):find("19", 1, true), boundary.." cannot revive offline direct writes")
  local finalcount = #w.sent
  stale(); staleupdate()
  staleconnect(); staledisconnect()
  eq(s.sk.prioritydisconnected, nil, boundary.." rejects replaced connection callbacks after live resume")
  eq(#w.sent, finalcount, boundary.." callbacks remain inert after live resume")
end

print("priority delivery: "..checks.." checks passed")
