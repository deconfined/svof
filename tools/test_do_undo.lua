-- Run from Sources/svof: lua tools/test_do_undo.lua
-- Uses the shipped Dor loader and native balance controller in svof_world.
-- expandAlias is only the Mudlet I/O boundary: these commands have no aliases.
local world = dofile("tools/svof_world.lua")
local checks = 0
local function eq(got, want, label)
  checks = checks + 1
  assert(got == want, label .. ": got " .. tostring(got) .. ", wanted " .. tostring(want))
end

local function new_world()
  local w = world.new({ class = "Runewarden" })
  local s = w.svo
  -- Enqueue while off balance. No core queue function is replaced.
  s.bals.balance = false
  s.bals.equilibrium, s.bals.leftarm, s.bals.rightarm = true, true, true
  s.me.dopaused = false
  w.expanded = {}
  w.env.expandAlias = function(command, show)
    w.expanded[#w.expanded + 1] = {command = command, show = show}
    w.env.send(command, show)
  end
  return w, s
end

local function event_count(w, name)
  local count = 0
  for _, event in ipairs(w.events) do
    if event.name == name then count = count + 1 end
  end
  return count
end

local function recover(w, s)
  -- The balance line updates the tick; the real controller then admits work.
  s.bals.balance = true
  s.gotbalance()
  s.sk.balance_controller()
  w.advance(0)
end

-- The reported fault: cancellation echoed success but LOOK still ran later.
for _, echo in ipairs({false, true}) do
  local w, s = new_world()
  s.doadd("LOOK")
  s.doadd("SCORE")
  s.doaddfree("INVENTORY")
  local queue = s.me.doqueue
  local freequeue = s.me.dofreequeue
  local before = event_count(w, "svo do changed")
  local freebefore = event_count(w, "svo dofree changed")
  s.undo(nil, echo)
  eq(s.me.doqueue, queue, "undo preserves the native queue object")
  eq(#queue, 1, "undo removes exactly one pending entry")
  eq(queue[1], "SCORE", "second entry remains first")
  eq(s.me.dofreequeue, freequeue, "undo does not replace unrelated free queue")
  eq(freequeue[1], "INVENTORY", "undo leaves unrelated free work pending")
  eq(event_count(w, "svo do changed"), before + 1, "undo emits one change event")
  eq(event_count(w, "svo dofree changed"), freebefore, "undo does not announce free changes")
  s.sk.balance_controller()
  eq(#w.expanded, 0, "off-balance controller cannot run either queue")
  recover(w, s)
  local commands = {}
  for _, entry in ipairs(w.expanded) do commands[#commands + 1] = entry.command end
  eq(table.concat(commands, ","), "INVENTORY,SCORE", "recovery runs surviving work, never LOOK")
  eq(#s.me.doqueue, 0, "surviving native command finishes normally")
  s.sk.balance_controller()
  eq(#w.expanded, 2, "same balance tick cannot run work twice")
end

-- Table entries are created by the real public show=false API. Removing the
-- first must not strip the surviving entry's command or its show setting.
do
  local w, s = new_world()
  s.doadd("LOOK", false, false)
  s.doadd("SCORE", false, false)
  local survivor = s.me.doqueue[2]
  s.undo(nil, true)
  eq(s.me.doqueue[1], survivor, "table survivor identity preserved")
  eq(survivor.show, false, "show=false remains attached to survivor")
  recover(w, s)
  eq(#w.expanded, 1, "only surviving table entry runs")
  eq(w.expanded[1].command, "SCORE", "table command forwarded by real dispatcher")
  eq(w.expanded[1].show, false, "table command remains hidden at Mudlet boundary")
end

-- Functions and explicit table/function entries are native queue payloads too.
for _, wrapped in ipairs({false, true}) do
  local w, s = new_world()
  local removed_runs, survivor_runs = 0, 0
  local removed = function() removed_runs = removed_runs + 1 end
  local survivor = function() survivor_runs = survivor_runs + 1 end
  if wrapped then
    s.doadd(removed, false, false)
    s.doadd(survivor, false, false)
  else
    s.doadd(removed)
    s.doadd(survivor)
  end
  s.undo(nil, true)
  recover(w, s)
  eq(removed_runs, 0, "removed function never executes")
  eq(survivor_runs, 1, "surviving function executes normally")
  eq(#s.me.doqueue, 0, "function survivor is consumed")
  eq(#w.expanded, 0, "function payloads do not invent server commands")
end

-- A top-only undo must not disable repeat mode or clear the second command.
do
  local w, s = new_world()
  s.dor("LOOK")
  s.doadd("SCORE", false, false)
  local queue = s.me.doqueue
  s.undo(nil, true)
  eq(s.me.doqueue, queue, "repeating queue object preserved")
  eq(queue.repeating, true, "repeat mode survives top-only undo")
  recover(w, s)
  eq(w.expanded[1].command, "SCORE", "next command runs in repeating mode")
  eq(w.expanded[1].show, false, "repeating survivor retains show=false")
  eq(#queue, 1, "repeating survivor remains queued")
  recover(w, s)
  eq(#w.expanded, 2, "survivor repeats on next balance tick")
  eq(w.expanded[2].command, "SCORE", "only survivor repeats")
  local before = event_count(w, "svo do changed")
  s.undo(nil, true)
  eq(#queue, 0, "undo removes the final repeating entry")
  eq(queue.repeating, true, "empty repeating mode remains enabled")
  eq(event_count(w, "svo do changed"), before + 1, "final removal emits change event")
  recover(w, s)
  eq(#w.expanded, 2, "empty repeating queue cannot run removed work")
  before = event_count(w, "svo do changed")
  s.undo(nil, true)
  eq(queue.repeating, true, "empty undo preserves repeat mode")
  eq(event_count(w, "svo do changed"), before, "empty undo does not invent a change")
end

-- Keep existing public distinctions: named undo selects its command rather
-- than the top; the 'all' token is reserved for the separate undoall alias;
-- undofree removes from its own queue, not the native balanceful do queue.
do
  local w, s = new_world()
  s.doadd("LOOK")
  s.doadd("SCORE", false, false)
  s.doadd("STATUS")
  s.doaddfree("INVENTORY")
  s.doaddfree("RIFT")
  s.undo("SCORE", true)
  eq(#s.me.doqueue, 2, "named undo removes selected table entry")
  eq(s.me.doqueue[1], "LOOK", "named undo preserves top command")
  eq(s.me.doqueue[2], "STATUS", "named undo preserves following command")
  s.undo("missing", false)
  eq(#s.me.doqueue, 2, "missing named undo leaves work intact")
  s.undo("all", true)
  eq(#s.me.doqueue, 2, "reserved all token does not become top-only undo")
  s.undofree(true)
  eq(#s.me.doqueue, 2, "undofree does not cancel native do work")
  eq(#s.me.dofreequeue, 1, "undofree removes only its first entry")
  eq(s.me.dofreequeue[1], "RIFT", "undofree preserves its second entry")
  s.undoall(false)
  eq(#s.me.doqueue, 0, "undoall still clears all native do work")
  eq(s.me.dofreequeue[1], "RIFT", "undoall leaves unrelated free work intact")
  local before = event_count(w, "svo do changed")
  s.undo(nil, true)
  eq(event_count(w, "svo do changed"), before, "empty ordinary queue undo is unchanged")
  recover(w, s)
  eq(#w.expanded, 1, "only surviving unrelated free work runs")
  eq(w.expanded[1].command, "RIFT", "surviving free command is dispatched normally")
end

print("ALL PASS (" .. checks .. " native undo checks)")
