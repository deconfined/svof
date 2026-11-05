--[[
Logic-level test for the limb counter, on svof's real source through
tools/svof_world.lua, so the world's signals, timers and GMCP handlers are the
shipped ones.

What it pins:

  * a hit adds the percentage the game reported, and only at the prompt.
  * a hit counts while off balance or equilibrium, however it was sent, and
    not while on both, which is the shape of an illusioned line.
  * damage keeps adding past a break, and doesn't drift on float rounding.
  * a limb's level follows its damage, 100 for level 2 and 200 for level 3.
  * DEVASTATE, which prints no damage line, puts both limbs of the pair at
    the level its line shows.
  * each salve takes one level off, restoration on the first limb in the area
    that needs it, and a salve is told from another by the salve balance.
  * a limb clears after svo.lc_forget_after seconds without a hit.
  * nn resets the selected target, vsl lists everyone, and prompt tags show
    the selected target's raw percentages and game break stages.
  * reloads and class changes preserve pending work and original timer deadlines
    without duplicating handlers; resets invalidate only the work they own.

The trigger patterns are not exercised, since the world doesn't load static
triggers. It proves nothing about Mudlet integration, the game, or real combat.

Run: lua tools/test_limbcounter.lua
Exits 0 and prints "ALL PASS" on success, exits 1 and prints failures.
]]

local world = dofile("tools/svof_world.lua")
local LC = arg and arg[1] or "src/scripts/svo (limbcounter)/svo_limbcounter.lua"

local passed, failed = 0, {}
local function check(name, fn)
  local ok, err = xpcall(fn, function(e) return debug.traceback(tostring(e), 2) end)
  if ok then passed = passed + 1 else failed[#failed + 1] = name .. "\n    " .. tostring(err):sub(1, 400) end
end
local function eq(got, want)
  if got ~= want then error("expected " .. tostring(want) .. ", got " .. tostring(got), 2) end
end

local function boot()
  local w = world.new({ class = "Runewarden" })
  w.run(world.read_file(LC), "limbcounter")
  w.env.target = "Bob"
  return w, w.svo
end

-- The prompt after a hit: GMCP's balances, then the signal svo.onprompt emits.
local function prompt(w, bal, equilibrium)
  w.env.gmcp.Char.Vitals = { bal = bal and "1" or "0", eq = equilibrium and "1" or "0" }
  w.svo.signals.gmcpcharvitals:emit()
  w.svo.signals.before_prompt_processing:emit()
end
local function off_balance(w) prompt(w, false, true) end

local function hit(w, who, where, amount)
  w.svo.lc_hit(who, where, amount)
  off_balance(w)
end

local function said(w, what)
  return table.concat(w.echoes, "|"):find(what, 1, true) ~= nil
end

local function plain(text)
  return text:gsub("<[^>]+>", "")
end

local function tags(svo)
  return { svo.lc_prompttag(), svo.lc_prompttag2(), svo.lc_prompttag3() }
end

local function blank_tags(svo)
  for _, text in ipairs(tags(svo)) do eq(text, "") end
end

local function event_count(w, name)
  local n = 0
  for _, event in ipairs(w.events) do
    if event.name == name then n = n + 1 end
  end
  return n
end

-- Capture a public world timer, not the tracker's private ownership records.
-- Calling a cancelled callback models one already dispatched by the host.
local function timer_at(w, delay)
  local found
  for _, timer in pairs(w.timers) do
    if math.abs(timer.at - (w.now + delay)) < 0.000001 then
      assert(not found, "ambiguous timer deadline")
      found = timer
    end
  end
  assert(found, "no timer at expected deadline")
  return function()
    if type(found.f) == "string" then w.run(found.f, "stale timer") else found.f() end
  end
end

local function reload(w)
  w.run(world.read_file(LC), "limbcounter reload")
end

check("a hit waits for the prompt", function()
  local w, svo = boot()
  svo.lc_hit("Bob", "left leg", 8.4)
  eq(svo.lc_damage("Bob", "left leg"), 0)
  off_balance(w)
  eq(svo.lc_damage("Bob", "left leg"), 8.4)
end)

check("hits add up, per limb and per person", function()
  local w, svo = boot()
  hit(w, "Bob", "left leg", 8.4); hit(w, "Bob", "left leg", 8.4); hit(w, "Bob", "right arm", 9.2)
  hit(w, "Ann", "left leg", 5)
  eq(svo.lc_list.Bob.leftleg, 16.8); eq(svo.lc_list.Bob.rightarm, 9.2); eq(svo.lc_list.Ann.leftleg, 5)
end)

check("several hits in one paragraph all count", function()
  local w, svo = boot()
  svo.lc_hit("Bob", "head", 8.9); svo.lc_hit("Bob", "left leg", 8.4); svo.lc_hit("Bob", "right leg", 8.4)
  off_balance(w)
  eq(svo.lc_list.Bob.head, 8.9); eq(svo.lc_list.Bob.leftleg, 8.4); eq(svo.lc_list.Bob.rightleg, 8.4)
end)

check("counts off balance, off equilibrium, or off both", function()
  local w, svo = boot()
  svo.lc_hit("Bob", "head", 1); prompt(w, false, true); eq(svo.lc_list.Bob.head, 1)
  svo.lc_hit("Bob", "head", 1); prompt(w, true, false); eq(svo.lc_list.Bob.head, 2)
  svo.lc_hit("Bob", "head", 1); prompt(w, false, false); eq(svo.lc_list.Bob.head, 3)
end)

check("a damage line while on both balances is an illusion", function()
  local w, svo = boot()
  svo.lc_hit("Bob", "head", 50)
  prompt(w, true, true)
  eq(svo.lc_damage("Bob", "head"), 0)
  eq(svo.lc_list.Bob, nil)
end)

check("a rejected hit doesn't carry over to the next prompt", function()
  local w, svo = boot()
  svo.lc_hit("Bob", "head", 50)
  prompt(w, true, true)
  off_balance(w)
  eq(svo.lc_damage("Bob", "head"), 0)
end)

check("damage keeps adding past a break", function()
  local w, svo = boot()
  hit(w, "Bob", "head", 97); hit(w, "Bob", "head", 13.4); hit(w, "Bob", "head", 100); hit(w, "Bob", "head", 100)
  eq(svo.lc_list.Bob.head, 310.4)
end)

check("float drift can't decide a break", function()
  local w, svo = boot()
  for _ = 1, 12 do hit(w, "Bob", "left leg", 8.4) end
  eq(svo.lc_list.Bob.leftleg, 100.8)
  local w2, svo2 = boot()
  for _ = 1, 10 do hit(w2, "Bob", "torso", 10.0) end
  eq(svo2.lc_list.Bob.torso, 100)
  eq(svo2.lc_list.Bob.torso >= svo2.lc_break_at, true)
end)

local function devastate(w, area, level)
  w.svo.lc_devastate("bob", area, level)
  off_balance(w)
end

check("DEVASTATE puts both limbs of the pair at its level", function()
  for level, want in ipairs({ 100, 100, 200 }) do
    local w, svo = boot()
    devastate(w, "legs", level)
    eq(svo.lc_level("Bob", "leftleg"), level); eq(svo.lc_level("Bob", "rightleg"), level)
    eq(svo.lc_damage("Bob", "leftleg"), want); eq(svo.lc_damage("Bob", "rightleg"), want)
    eq(svo.lc_level("Bob", "leftarm"), 0); eq(svo.lc_damage("Bob", "head"), 0)
  end
end)

check("DEVASTATE at level 1 reads as broken with no damage behind it", function()
  local w, svo = boot()
  devastate(w, "legs", 1)
  eq(svo.lc_list.Bob.leftleg, 0); eq(svo.lc_damage("Bob", "left leg"), 100)
end)

check("DEVASTATE ARMS takes the arms", function()
  local w, svo = boot()
  devastate(w, "arms", 2)
  eq(svo.lc_list.Bob.leftarm, 100); eq(svo.lc_list.Bob.rightarm, 100); eq(svo.lc_list.Bob.leftleg, 0)
end)

check("DEVASTATE raises a damaged limb to its level", function()
  local w, svo = boot()
  hit(w, "Bob", "left leg", 42)
  devastate(w, "legs", 3)
  eq(svo.lc_list.Bob.leftleg, 200); eq(svo.lc_list.Bob.rightleg, 200)
end)

check("DEVASTATE never lowers a limb", function()
  local w, svo = boot()
  hit(w, "Bob", "left leg", 250)
  devastate(w, "legs", 1)
  eq(svo.lc_list.Bob.leftleg, 250); eq(svo.lc_level("Bob", "leftleg"), 3)
  eq(svo.lc_level("Bob", "rightleg"), 1)
end)

check("DEVASTATE takes an already broken limb a level past where it was", function()
  local w, svo = boot()
  devastate(w, "arms", 1)
  devastate(w, "arms", 1)
  eq(svo.lc_level("Bob", "leftarm"), 2); eq(svo.lc_damage("Bob", "leftarm"), 100)
  devastate(w, "arms", 2)
  eq(svo.lc_level("Bob", "leftarm"), 3); eq(svo.lc_damage("Bob", "leftarm"), 200)
end)

check("a higher DEVASTATE on a broken limb goes to its own level, not past it", function()
  local w, svo = boot()
  devastate(w, "legs", 1)
  devastate(w, "legs", 2)
  eq(svo.lc_level("Bob", "leftleg"), 2)
  local w2, svo2 = boot()
  devastate(w2, "legs", 1)
  devastate(w2, "legs", 3)
  eq(svo2.lc_level("Bob", "leftleg"), 3)
end)

check("a limb broken by damage counts as already broken", function()
  local w, svo = boot()
  hit(w, "Bob", "left leg", 150)
  devastate(w, "legs", 2)
  eq(svo.lc_level("Bob", "leftleg"), 3); eq(svo.lc_list.Bob.leftleg, 200)
end)

check("DEVASTATE judges each limb of the pair by itself", function()
  local w, svo = boot()
  hit(w, "Bob", "left leg", 150)
  devastate(w, "legs", 2)
  eq(svo.lc_level("Bob", "leftleg"), 3); eq(svo.lc_level("Bob", "rightleg"), 2)
end)

check("damage short of a break doesn't count as already broken", function()
  local w, svo = boot()
  hit(w, "Bob", "left leg", 99)
  devastate(w, "legs", 1)
  eq(svo.lc_level("Bob", "leftleg"), 1)
end)

check("a limb that mending finished is no longer already broken", function()
  local w, svo = boot()
  devastate(w, "legs", 1)
  svo.lc_salve("Bob", "legs")
  svo.lc_salve("Bob", "legs")
  devastate(w, "legs", 1)
  eq(svo.lc_level("Bob", "leftleg"), 1); eq(svo.lc_level("Bob", "rightleg"), 1)
end)

check("hits keep adding on top of a DEVASTATE", function()
  local w, svo = boot()
  devastate(w, "legs", 2)
  hit(w, "Bob", "left leg", 8.4)
  eq(svo.lc_list.Bob.leftleg, 108.4)
end)

check("a limb broken with no damage reads 100 until its damage passes that", function()
  local w, svo = boot()
  devastate(w, "legs", 1)
  hit(w, "Bob", "left leg", 60)
  eq(svo.lc_list.Bob.leftleg, 60); eq(svo.lc_damage("Bob", "leftleg"), 100); eq(svo.lc_level("Bob", "leftleg"), 1)
  hit(w, "Bob", "left leg", 45)
  eq(svo.lc_damage("Bob", "leftleg"), 105); eq(svo.lc_level("Bob", "leftleg"), 2)
end)

check("a DEVASTATE line while on both balances is an illusion", function()
  local w, svo = boot()
  svo.lc_devastate("Bob", "legs", 3)
  prompt(w, true, true)
  eq(svo.lc_list.Bob, nil)
end)

check("DEVASTATE ignores an area it doesn't know", function()
  local w, svo = boot()
  devastate(w, "head", 1)
  eq(svo.lc_list.Bob, nil)
end)

check("DEVASTATE doesn't count as the last hit size for prepped", function()
  local w, svo = boot()
  hit(w, "Bob", "head", 30)
  devastate(w, "legs", 3)
  hit(w, "Bob", "torso", 75)
  eq(svo.lc_prepped("Bob", "head"), true)
  local w2, svo2 = boot()
  hit(w2, "Bob", "head", 60)
  hit(w2, "Bob", "torso", 5)
  devastate(w2, "legs", 3)
  eq(svo2.lc_prepped("Bob", "head"), false)
end)

check("DEVASTATE raises the hit event with what it added", function()
  local w = boot()
  w.svo.lc_devastate("Bob", "legs", 2)
  off_balance(w)
  local e = w.events[#w.events]
  eq(e.name, "svo limbcounter hit"); eq(e.args[2], "rightleg"); eq(e.args[3], 100)
end)

check("restoration takes one limb of a devastated pair at a time", function()
  local w, svo = boot()
  devastate(w, "legs", 2)
  svo.lc_salve("Bob", "legs")
  w.advance(4)
  eq(svo.lc_level("Bob", "leftleg"), 1); eq(svo.lc_level("Bob", "rightleg"), 2)
end)

-- One salve at the timing the game allows: restoration holds the salve balance for 4 seconds.
local function restoration(w, area) w.svo.lc_salve("Bob", area); w.advance(4) end

check("a level 3 DEVASTATE takes restoration, restoration, mending", function()
  local w, svo = boot()
  devastate(w, "legs", 3)
  restoration(w, "legs")
  eq(svo.lc_level("Bob", "leftleg"), 2); eq(svo.lc_damage("Bob", "leftleg"), 100)
  restoration(w, "legs")
  eq(svo.lc_level("Bob", "leftleg"), 1); eq(svo.lc_damage("Bob", "leftleg"), 100)
  eq(svo.lc_list.Bob.leftleg, 0)
end)

check("a mangled limb takes restoration, restoration, mending", function()
  local w, svo = boot()
  hit(w, "Bob", "left arm", 230)
  eq(svo.lc_level("Bob", "leftarm"), 3)
  restoration(w, "arms")
  eq(svo.lc_level("Bob", "leftarm"), 2); eq(svo.lc_list.Bob.leftarm, 100)
  restoration(w, "arms")
  eq(svo.lc_level("Bob", "leftarm"), 1); eq(svo.lc_list.Bob.leftarm, 0)
  svo.lc_salve("Bob", "arms")
  eq(svo.lc_level("Bob", "leftarm"), 0); eq(svo.lc_damage("Bob", "leftarm"), 0)
end)

check("restoration leaves a damaged limb broken, and mending finishes it", function()
  local w, svo = boot()
  hit(w, "Bob", "left leg", 120)
  eq(svo.lc_level("Bob", "leftleg"), 2)
  restoration(w, "legs")
  eq(svo.lc_list.Bob.leftleg, 0); eq(svo.lc_damage("Bob", "leftleg"), 100)
  svo.lc_salve("Bob", "legs")
  eq(svo.lc_damage("Bob", "leftleg"), 0)
end)

check("head and torso heal outright from level 2, and step down from 3", function()
  for _, part in ipairs({ { "head", "head" }, { "torso", "body" } }) do
    local w, svo = boot()
    hit(w, "Bob", part[1], 210)
    eq(svo.lc_level("Bob", part[1]), 3)
    restoration(w, part[2])
    eq(svo.lc_level("Bob", part[1]), 2); eq(svo.lc_list.Bob[part[1]], 100)
    restoration(w, part[2])
    eq(svo.lc_level("Bob", part[1]), 0); eq(svo.lc_damage("Bob", part[1]), 0)
  end
end)

check("mending acts at once, one limb to a salve, left first", function()
  local w, svo = boot()
  devastate(w, "legs", 1)
  svo.lc_salve("Bob", "legs")
  eq(svo.lc_level("Bob", "leftleg"), 0); eq(svo.lc_level("Bob", "rightleg"), 1)
  svo.lc_salve("Bob", "legs")
  eq(svo.lc_level("Bob", "rightleg"), 0)
end)

check("mending keeps damage dealt since the break", function()
  local w, svo = boot()
  devastate(w, "legs", 1)
  hit(w, "Bob", "left leg", 30)
  svo.lc_salve("Bob", "legs")
  eq(svo.lc_list.Bob.leftleg, 30); eq(svo.lc_level("Bob", "leftleg"), 0)
  w.advance(180); eq(svo.lc_list.Bob.leftleg, 0)
end)

check("a salve before restoration could land means it wasn't restoration", function()
  local w, svo = boot()
  hit(w, "Bob", "left leg", 120)
  svo.lc_salve("Bob", "legs")
  w.advance(1)
  svo.lc_salve("Bob", "skin")
  w.advance(10)
  eq(svo.lc_list.Bob.leftleg, 120); eq(svo.lc_level("Bob", "leftleg"), 2)
end)

check("that salve was mending, so it takes a broken limb in its area", function()
  local w, svo = boot()
  devastate(w, "legs", 1)
  hit(w, "Bob", "left leg", 120)
  svo.lc_salve("Bob", "legs")
  eq(svo.lc_level("Bob", "rightleg"), 1)
  w.advance(1)
  svo.lc_salve("Bob", "skin")
  eq(svo.lc_level("Bob", "rightleg"), 0); eq(svo.lc_level("Bob", "leftleg"), 2)
end)

check("a limb broken while restoration is on its way takes the cure, left first", function()
  local w, svo = boot()
  hit(w, "Bob", "right leg", 120)
  svo.lc_salve("Bob", "legs")
  w.advance(2)
  hit(w, "Bob", "left leg", 120)
  w.advance(2)
  eq(svo.lc_level("Bob", "leftleg"), 1); eq(svo.lc_level("Bob", "rightleg"), 2)
end)

check("restoration's own next salve doesn't undo it", function()
  local w, svo = boot()
  hit(w, "Bob", "left leg", 120); hit(w, "Bob", "right leg", 120)
  svo.lc_salve("Bob", "legs")
  w.advance(3.7)
  eq(svo.lc_level("Bob", "leftleg"), 1)
  svo.lc_salve("Bob", "legs")
  eq(svo.lc_level("Bob", "leftleg"), 1)
  w.advance(3.7)
  eq(svo.lc_level("Bob", "rightleg"), 1)
end)

check("damage counts from nothing after restoration", function()
  local w, svo = boot()
  hit(w, "Bob", "left leg", 120)
  restoration(w, "legs")
  hit(w, "Bob", "left leg", 8.4)
  eq(svo.lc_list.Bob.leftleg, 8.4); eq(svo.lc_level("Bob", "leftleg"), 1)
end)

check("level stops at 3", function()
  local w, svo = boot()
  hit(w, "Bob", "left leg", 350)
  eq(svo.lc_level("Bob", "leftleg"), 3)
end)

check("each salve that changes a limb raises one reset event", function()
  local count = function(w)
    local n = 0
    for _, e in ipairs(w.events) do if e.name == "svo limbcounter reset" then n = n + 1 end end
    return n
  end
  local w, svo = boot()
  hit(w, "Bob", "left leg", 120)
  restoration(w, "legs"); eq(count(w), 1)
  svo.lc_salve("Bob", "legs"); eq(count(w), 2)
end)

check("a stage-only break displays raw zero without changing the combat accessor", function()
  local w, svo = boot()
  devastate(w, "legs", 1)
  hit(w, "Ann", "head", 8.4)
  eq(svo.lc_lasthit, "Ann")
  eq(svo.lc_list.Bob.leftleg, 0); eq(svo.lc_damage("Bob", "leftleg"), 100)
  eq(svo.lc_level("Bob", "leftleg"), 1)
  for _, text in ipairs(tags(svo)) do
    assert(plain(text):find("0% [L1]", 1, true), text)
    assert(not plain(text):find("100% [L1]", 1, true), text)
  end
  assert(said(w, "0% [L1]"))
  svo.lc_show()
  assert(said(w, "leftleg 0% [L1]"))
  eq(svo.lc_damage("Bob", "leftleg"), 100)
end)

check("running the loader again keeps levels", function()
  local w, svo = boot()
  hit(w, "Bob", "left leg", 120)
  w.run(world.read_file(LC), "limbcounter")
  eq(w.svo.lc_level("Bob", "leftleg"), 2)
end)

check("levels are cleared with the limb", function()
  local w, svo = boot()
  hit(w, "Bob", "head", 120)
  w.advance(180); eq(svo.lc_level("Bob", "head"), 0)
  hit(w, "Bob", "head", 120)
  svo.lc_reset("h"); eq(svo.lc_level("Bob", "head"), 0)
  hit(w, "Bob", "head", 120)
  svo.lc_reset(); eq(svo.lc_level("Bob", "head"), 0)
  hit(w, "Bob", "head", 120)
  svo.lc_reset("all"); eq(svo.lc_level("Bob", "head"), 0)
end)

check("reads level 0 for someone it isn't tracking, and takes either limb spelling", function()
  local w, svo = boot()
  eq(svo.lc_level("Nobody", "head"), 0)
  hit(w, "Bob", "left leg", 120)
  eq(svo.lc_level("Bob", "left leg"), 2); eq(svo.lc_level("Bob", "leftleg"), 2)
end)

check("forgetting someone drops a cure on its way", function()
  local w, svo = boot()
  hit(w, "Bob", "left leg", 120)
  svo.lc_salve("Bob", "legs")
  svo.lc_reset()
  hit(w, "Bob", "left leg", 120)
  w.advance(4)
  eq(svo.lc_level("Bob", "leftleg"), 2)
end)

check("takes a limb with or without the space, in any name case", function()
  local w, svo = boot()
  hit(w, "bOB", "leftleg", 1); hit(w, "Bob", "left leg", 1)
  eq(svo.lc_list.Bob.leftleg, 2)
  eq(svo.lc_damage("Bob", "leftleg"), 2)
end)

check("ignores a limb it doesn't know and a bad amount", function()
  local w, svo = boot()
  hit(w, "Bob", "tail", 5); hit(w, "Bob", "head", "lots")
  eq(svo.lc_list.Bob, nil)
end)

check("reads 0 for someone it isn't tracking", function()
  local _, svo = boot()
  eq(svo.lc_damage("Nobody", "head"), 0); eq(svo.lc_damage(nil, "head"), 0)
end)

check("raises the hit event with who, where and how much", function()
  local w, svo = boot()
  hit(w, "Bob", "left leg", 8.4)
  local e = w.events[#w.events]
  eq(e.name, "svo limbcounter hit"); eq(e.args[1], "Bob"); eq(e.args[2], "leftleg"); eq(e.args[3], 8.4)
  eq(svo.lc_lasthit, "Bob")
end)

check("hit echoes carry the raw damage and stage", function()
  local w, svo = boot()
  hit(w, "Bob", "head", 30)
  assert(said(w, "30%"))
  eq(svo.lc_prepped("Bob", "head"), false)
  hit(w, "Bob", "head", 40)
  assert(said(w, "70%"))
  eq(svo.lc_prepped("Bob", "head"), true)
  hit(w, "Bob", "head", 40)
  assert(said(w, "110% [L2]"))
  eq(svo.lc_prepped("Bob", "head"), false)
end)

check("prepped follows the size of the last hit", function()
  local w, svo = boot()
  hit(w, "Bob", "head", 30)
  eq(svo.lc_prepped("Bob", "head"), false)
  hit(w, "Bob", "torso", 70)
  eq(svo.lc_prepped("Bob", "head"), true)
  hit(w, "Bob", "torso", 5)
  eq(svo.lc_prepped("Bob", "head"), false)
end)

check("a broken limb isn't prepped", function()
  local w, svo = boot()
  hit(w, "Bob", "head", 120)
  eq(svo.lc_prepped("Bob", "head"), false)
end)

check("other limbs remain prepped after a hit elsewhere", function()
  local w, svo = boot()
  hit(w, "Bob", "head", 70); hit(w, "Bob", "torso", 70)
  eq(svo.lc_prepped("Bob", "head"), true)
  eq(svo.lc_prepped("Bob", "torso"), true)
end)

check("a limb clears after the forget time", function()
  local w, svo = boot()
  hit(w, "Bob", "head", 30)
  w.advance(179); eq(svo.lc_list.Bob.head, 30)
  w.advance(1); eq(svo.lc_list.Bob.head, 0)
end)

check("a new hit restarts that limb's forget time, not the others'", function()
  local w, svo = boot()
  hit(w, "Bob", "head", 30); hit(w, "Bob", "torso", 30)
  w.advance(100)
  hit(w, "Bob", "head", 1)
  w.advance(80)
  eq(svo.lc_list.Bob.head, 31); eq(svo.lc_list.Bob.torso, 0)
  w.advance(100)
  eq(svo.lc_list.Bob.head, 0)
end)

check("a cure lands after the delay", function()
  local w, svo = boot()
  hit(w, "Bob", "left leg", 120)
  svo.lc_salve("Bob", "legs")
  w.advance(3.6); eq(svo.lc_list.Bob.leftleg, 120)
  w.advance(0.1); eq(svo.lc_list.Bob.leftleg, 0)
end)

check("a cure takes the left limb first, and only one", function()
  local w, svo = boot()
  hit(w, "Bob", "left arm", 120); hit(w, "Bob", "right arm", 120)
  svo.lc_salve("Bob", "arms")
  w.advance(4)
  eq(svo.lc_list.Bob.leftarm, 0); eq(svo.lc_list.Bob.rightarm, 120)
end)

check("a cure reaches the right limb when the left isn't broken", function()
  local w, svo = boot()
  hit(w, "Bob", "left arm", 50); hit(w, "Bob", "right arm", 120)
  svo.lc_salve("Bob", "arms")
  w.advance(4)
  eq(svo.lc_list.Bob.leftarm, 50); eq(svo.lc_list.Bob.rightarm, 0)
end)

check("a cure leaves an unbroken limb alone", function()
  local w, svo = boot()
  hit(w, "Bob", "head", 99.9)
  svo.lc_salve("Bob", "head")
  w.advance(4)
  eq(svo.lc_list.Bob.head, 99.9)
end)

check("body means torso, and an unknown area or person is ignored", function()
  local w, svo = boot()
  hit(w, "Bob", "torso", 120)
  svo.lc_salve("Bob", "skin"); svo.lc_salve("Nobody", "legs")
  w.advance(4); eq(svo.lc_list.Bob.torso, 120)
  svo.lc_salve("Bob", "body")
  w.advance(4); eq(svo.lc_list.Bob.torso, 0)
end)

check("a cleared limb stops its forget timer", function()
  local w, svo = boot()
  hit(w, "Bob", "head", 120)
  svo.lc_salve("Bob", "head")
  w.advance(4)
  hit(w, "Bob", "head", 10)
  w.advance(100); eq(svo.lc_list.Bob.head, 10)
end)

check("nn resets the current target, not the last person hit", function()
  local w, svo = boot()
  hit(w, "Ann", "head", 10); hit(w, "Bob", "head", 20)
  w.env.target = "  aNN  "
  svo.lc_reset()
  eq(svo.lc_list.Ann, nil); eq(svo.lc_list.Bob.head, 20)
  eq(svo.lc_lasthit, "Bob")
end)

check("nn with an empty capture resets the current target", function()
  local w, svo = boot()
  hit(w, "Ann", "head", 10); hit(w, "Bob", "head", 20)
  w.env.target = "Ann"
  svo.lc_reset("")
  eq(svo.lc_list.Ann, nil); eq(svo.lc_list.Bob.head, 20)
end)

check("nn <limb> resets one limb of the current target", function()
  local w, svo = boot()
  hit(w, "Ann", "left leg", 11); hit(w, "Ann", "head", 12)
  hit(w, "Bob", "left leg", 21)
  w.env.target = "Ann"
  svo.lc_reset("ll")
  eq(svo.lc_list.Ann.leftleg, 0); eq(svo.lc_list.Ann.head, 12)
  eq(svo.lc_list.Bob.leftleg, 21)
end)

check("nn <person> and nn all", function()
  local w, svo = boot()
  hit(w, "Ann", "head", 10); hit(w, "Bob", "head", 10); hit(w, "Cid", "head", 10)
  svo.lc_reset("ann")
  eq(svo.lc_list.Ann, nil); eq(svo.lc_list.Bob.head, 10)
  svo.lc_reset("all")
  eq(next(svo.lc_list), nil)
end)

check("resetting untracked people cannot create state", function()
  local w, svo = boot()
  w.env.target = "Nobody"
  svo.lc_reset(); svo.lc_reset("ll"); svo.lc_reset("Nobody")
  eq(next(svo.lc_list), nil)
  blank_tags(svo)
end)

check("a reset kills the limb's forget timer", function()
  local w, svo = boot()
  hit(w, "Bob", "head", 10)
  svo.lc_reset()
  hit(w, "Bob", "head", 20)
  w.advance(100); hit(w, "Bob", "torso", 1); svo.lc_reset("t")
  w.advance(100)
  eq(svo.lc_list.Bob.head, 0); eq(svo.lc_list.Bob.torso, 0)
end)

local function resets(w)
  local n = 0
  for _, e in ipairs(w.events) do if e.name == "svo limbcounter reset" then n = n + 1 end end
  return n
end

check("forgetting a limb raises the reset event", function()
  local w = boot()
  hit(w, "Bob", "head", 10)
  w.advance(180)
  eq(resets(w), 1)
end)

check("a cure raises one reset event, and cancels the limb's forget timer", function()
  local w, svo = boot()
  hit(w, "Bob", "head", 120)
  svo.lc_salve("Bob", "head")
  w.advance(200)
  eq(resets(w), 1)
end)

check("nn <limb> cancels the limb's forget timer", function()
  local w, svo = boot()
  hit(w, "Bob", "head", 10)
  svo.lc_reset("h")
  w.advance(200)
  eq(resets(w), 1)
end)

check("a reset raises the reset event", function()
  local w, svo = boot()
  hit(w, "Bob", "head", 10)
  svo.lc_reset()
  eq(w.events[#w.events].name, "svo limbcounter reset")
end)

check("vsl lists every tracked person regardless of target", function()
  local w, svo = boot()
  svo.lc_show()
  eq(next(svo.lc_list), nil)
  hit(w, "Bob", "head", 8.9); hit(w, "Ann", "head", 17.3)
  w.env.target = "Cid"
  w.echoes = {}
  svo.lc_show()
  assert(said(w, "Bob")); assert(said(w, "Ann"))
  assert(said(w, "head 8.9%")); assert(said(w, "head 17.3%"))
end)

check("all prompt tags follow the current target rather than the last hit", function()
  local w, svo = boot()
  blank_tags(svo)
  hit(w, "Ann", "left leg", 8.4); hit(w, "Bob", "left leg", 19.7)
  w.env.target = "  aNN  "
  eq(svo.lc_lasthit, "Bob")
  for _, text in ipairs(tags(svo)) do
    assert(plain(text):find("8.4", 1, true), text)
    assert(not plain(text):find("19.7", 1, true), text)
    assert(not plain(text):find("[L0]", 1, true), text)
  end
  assert(svo.lc_prompttag2():find("Ann", 1, true))
  w.env.target = "Bob"
  for _, text in ipairs(tags(svo)) do
    assert(plain(text):find("19.7", 1, true), text)
    assert(not plain(text):find("8.4", 1, true), text)
  end
end)

check("the prompt tags go red on the current target's broken or prepped limb", function()
  local w, svo = boot()
  hit(w, "Ann", "left arm", 10); hit(w, "Bob", "head", 3)
  w.env.target = "Ann"
  assert(not svo.lc_prompttag():find("<a_red>10", 1, true))
  hit(w, "Ann", "left arm", 60); hit(w, "Bob", "head", 3)
  assert(svo.lc_prompttag():find("<a_red>70", 1, true))
  hit(w, "Ann", "left arm", 35); hit(w, "Bob", "head", 3)
  assert(svo.lc_prompttag():find("<a_red>105", 1, true))
end)

check("reloads leave exactly one prompt handler calling the current implementation", function()
  local w, svo = boot()
  reload(w); svo.loader.limbcounter(); reload(w)
  local calls, original = 0, svo.lc_checklimbcounter
  svo.lc_checklimbcounter = function(...)
    calls = calls + 1
    return original(...)
  end
  hit(w, "Bob", "head", 10)
  eq(calls, 1); eq(svo.lc_list.Bob.head, 10)
  eq(event_count(w, "svo limbcounter hit"), 1)
end)

check("a valid expiry keeps its original deadline across reload", function()
  local w, svo = boot()
  hit(w, "Bob", "head", 30)
  w.advance(100); reload(w)
  w.advance(79); eq(svo.lc_list.Bob.head, 30)
  w.advance(1); eq(svo.lc_list.Bob.head, 0)
  eq(event_count(w, "svo limbcounter reset"), 1)
end)

check("an old expiry cannot erase a newer hit after reload", function()
  local w, svo = boot()
  hit(w, "Bob", "head", 30)
  w.advance(100); reload(w)
  hit(w, "Bob", "head", 1)
  w.advance(80); eq(svo.lc_list.Bob.head, 31)
  w.advance(99); eq(svo.lc_list.Bob.head, 31)
  w.advance(1); eq(svo.lc_list.Bob.head, 0)
  eq(event_count(w, "svo limbcounter reset"), 1)
end)

check("a valid pending cure keeps its original deadline across reload", function()
  local w, svo = boot()
  hit(w, "Bob", "left leg", 120)
  svo.lc_salve("Bob", "legs")
  w.advance(1); reload(w)
  w.advance(2.6); eq(svo.lc_list.Bob.leftleg, 120)
  w.advance(0.1); eq(svo.lc_list.Bob.leftleg, 0)
  eq(svo.lc_level("Bob", "leftleg"), 1)
  eq(event_count(w, "svo limbcounter reset"), 1)
end)

check("reset after reload cancels the old cure before new damage", function()
  local w, svo = boot()
  hit(w, "Bob", "left leg", 120)
  svo.lc_salve("Bob", "legs")
  w.advance(1); reload(w)
  svo.lc_reset("Bob")
  hit(w, "Bob", "left leg", 140)
  w.advance(3)
  eq(svo.lc_list.Bob.leftleg, 140); eq(svo.lc_level("Bob", "leftleg"), 2)
end)

check("reload preserves queued hits and DEVASTATE exactly once", function()
  local w, svo = boot()
  svo.lc_hit("Bob", "head", 8.4)
  svo.lc_devastate("Bob", "legs", 1)
  reload(w); svo.loader.limbcounter()
  off_balance(w)
  eq(svo.lc_list.Bob.head, 8.4)
  eq(svo.lc_list.Bob.leftleg, 0); eq(svo.lc_level("Bob", "leftleg"), 1)
  eq(svo.lc_level("Bob", "rightleg"), 1)
  eq(event_count(w, "svo limbcounter hit"), 3)
  off_balance(w)
  eq(svo.lc_list.Bob.head, 8.4); eq(svo.lc_level("Bob", "leftleg"), 1)
  eq(event_count(w, "svo limbcounter hit"), 3)
end)

check("reload preserves last hit size for prepped decisions", function()
  local w, svo = boot()
  hit(w, "Bob", "head", 30); hit(w, "Bob", "torso", 70)
  eq(svo.lc_prepped("Bob", "head"), true)
  reload(w)
  eq(svo.lc_prepped("Bob", "head"), true)
  devastate(w, "legs", 1)
  eq(svo.lc_prepped("Bob", "head"), true)
end)

check("named reset cancels queued work only for that person", function()
  local w, svo = boot()
  svo.lc_hit("Bob", "head", 8.4); svo.lc_devastate("Bob", "legs", 2)
  svo.lc_hit("Ann", "head", 17.3)
  svo.lc_reset("Bob")
  svo.lc_hit("Bob", "torso", 9.2)
  off_balance(w)
  eq(svo.lc_list.Bob.head, 0); eq(svo.lc_list.Bob.torso, 9.2)
  eq(svo.lc_level("Bob", "leftleg"), 0); eq(svo.lc_level("Bob", "rightleg"), 0)
  eq(svo.lc_list.Ann.head, 17.3)
  eq(event_count(w, "svo limbcounter hit"), 2)
end)

check("reset from a hit consumer cancels the rest of that person's paragraph", function()
  local w, svo = boot()
  local record_event, reset_once = w.env.raiseEvent, false
  w.env.raiseEvent = function(name, who, where, ...)
    record_event(name, who, where, ...)
    if name == "svo limbcounter hit" and who == "Bob" and where == "head" and not reset_once then
      reset_once = true
      svo.lc_reset("Bob")
      svo.lc_hit("Bob", "right arm", 7)
    end
  end
  svo.lc_hit("Bob", "head", 10)
  svo.lc_hit("Bob", "torso", 20)
  svo.lc_hit("Ann", "left leg", 30)
  off_balance(w)
  eq(svo.lc_list.Bob, nil)
  eq(svo.lc_damage("Ann", "leftleg"), 30)
  off_balance(w)
  eq(svo.lc_damage("Bob", "head"), 0)
  eq(svo.lc_damage("Bob", "torso"), 0)
  eq(svo.lc_damage("Bob", "rightarm"), 7)
  eq(svo.lc_damage("Ann", "leftleg"), 30)
end)

check("global reset cancels pending-only people before the prompt", function()
  local w, svo = boot()
  svo.lc_hit("Bob", "head", 8.4); svo.lc_devastate("Ann", "arms", 3)
  eq(next(svo.lc_list), nil)
  svo.lc_reset("all")
  svo.lc_hit("Cid", "head", 4.2)
  off_balance(w)
  eq(svo.lc_list.Bob, nil); eq(svo.lc_list.Ann, nil); eq(svo.lc_list.Cid.head, 4.2)
  eq(event_count(w, "svo limbcounter hit"), 1)
end)

check("limb reset cancels its queued hits and DEVASTATE but preserves unrelated work", function()
  local w, svo = boot()
  svo.lc_hit("Bob", "left leg", 8.4); svo.lc_devastate("Bob", "legs", 2)
  svo.lc_hit("Bob", "head", 9.2); svo.lc_hit("Ann", "left leg", 17.3)
  svo.lc_reset("Bob left leg")
  svo.lc_hit("Bob", "left leg", 4.2)
  off_balance(w)
  eq(svo.lc_list.Bob.leftleg, 4.2); eq(svo.lc_level("Bob", "leftleg"), 0)
  eq(svo.lc_list.Bob.rightleg, 100); eq(svo.lc_level("Bob", "rightleg"), 2)
  eq(svo.lc_list.Bob.head, 9.2); eq(svo.lc_list.Ann.leftleg, 17.3)
  eq(event_count(w, "svo limbcounter hit"), 4)
end)

check("limb reset invalidates its area cure but leaves other people and expiry work", function()
  local w, svo = boot()
  hit(w, "Bob", "left leg", 120); hit(w, "Bob", "right leg", 120)
  hit(w, "Bob", "head", 15); hit(w, "Ann", "left leg", 120)
  svo.lc_salve("Bob", "legs"); svo.lc_salve("Ann", "legs")
  w.advance(1); reload(w)
  svo.lc_reset("Bob ll")
  hit(w, "Bob", "left leg", 140)
  w.advance(3)
  eq(svo.lc_list.Bob.leftleg, 140); eq(svo.lc_list.Bob.rightleg, 120)
  eq(svo.lc_level("Ann", "leftleg"), 1); eq(svo.lc_list.Bob.head, 15)
  w.advance(176)
  eq(svo.lc_list.Bob.head, 0); eq(svo.lc_list.Bob.rightleg, 0)
  eq(svo.lc_list.Bob.leftleg, 140)
end)

check("limb reset leaves a pending cure in another area alone", function()
  local w, svo = boot()
  hit(w, "Bob", "head", 12); hit(w, "Bob", "left leg", 120)
  svo.lc_salve("Bob", "legs")
  svo.lc_reset("Bob h")
  w.advance(3.7)
  eq(svo.lc_list.Bob.head, 0); eq(svo.lc_level("Bob", "leftleg"), 1)
end)

check("global reset cancels live cures and expiry after reload", function()
  local w, svo = boot()
  hit(w, "Bob", "head", 120); hit(w, "Ann", "head", 130)
  svo.lc_salve("Bob", "head"); svo.lc_salve("Ann", "head")
  w.advance(1); reload(w); svo.lc_reset("all")
  hit(w, "Bob", "head", 140); hit(w, "Ann", "head", 150)
  w.advance(179)
  eq(svo.lc_list.Bob.head, 140); eq(svo.lc_list.Ann.head, 150)
  w.advance(1)
  eq(svo.lc_list.Bob.head, 0); eq(svo.lc_list.Ann.head, 0)
end)

check("a dispatched stale expiry cannot clear newer timer ownership", function()
  local w, svo = boot()
  hit(w, "Bob", "head", 10)
  local stale = timer_at(w, 180)
  w.advance(1); reload(w); hit(w, "Bob", "head", 20)
  stale()
  eq(svo.lc_list.Bob.head, 30)
  svo.lc_reset("Bob")
  hit(w, "Bob", "head", 40)
  local count = event_count(w, "svo limbcounter reset")
  w.advance(179); eq(svo.lc_list.Bob.head, 40)
  eq(event_count(w, "svo limbcounter reset"), count)
  w.advance(1); eq(svo.lc_list.Bob.head, 0)
  eq(event_count(w, "svo limbcounter reset"), count + 1)
end)

check("a dispatched stale cure cannot clear newer cure ownership", function()
  local w, svo = boot()
  hit(w, "Bob", "head", 120); svo.lc_salve("Bob", "head")
  local stale = timer_at(w, 3.7)
  w.advance(1); reload(w); svo.lc_reset("Bob")
  hit(w, "Bob", "head", 140); svo.lc_salve("Bob", "head")
  stale()
  eq(svo.lc_list.Bob.head, 140)
  w.advance(1); svo.lc_salve("Bob", "skin")
  w.advance(4)
  eq(svo.lc_list.Bob.head, 140); eq(svo.lc_level("Bob", "head"), 2)
end)

check("the real class-change path preserves pending work and timer deadlines", function()
  local w, svo = boot()
  hit(w, "Bob", "head", 30); hit(w, "Bob", "torso", 120)
  svo.lc_salve("Bob", "body")
  w.advance(1)
  svo.lc_hit("Ann", "head", 7); svo.lc_devastate("Bob", "legs", 1)
  local count = event_count(w, "svo limbcounter hit")
  svo.classchange("Monk")
  eq(svo.me.class, "Monk"); eq(svo.systemloaded, true)
  off_balance(w)
  eq(svo.lc_list.Ann.head, 7); eq(svo.lc_level("Bob", "leftleg"), 1)
  eq(event_count(w, "svo limbcounter hit"), count + 3)
  off_balance(w)
  eq(event_count(w, "svo limbcounter hit"), count + 3)
  w.advance(2.6); eq(svo.lc_list.Bob.torso, 120)
  w.advance(0.1); eq(svo.lc_list.Bob.torso, 0)
  w.advance(176.3); eq(svo.lc_list.Bob.head, 0)
  eq(svo.lc_list.Ann.head, 7)
end)

local reset_limbs = {
  { "head", "h", "HEAD" }, { "torso", "t", "Torso" },
  { "leftarm", "la", "LEFTARM", " Left Arm " }, { "rightarm", "ra", "RIGHTARM", " Right Arm " },
  { "leftleg", "ll", "LEFTLEG", " Left Leg " }, { "rightleg", "rl", "RIGHTLEG", " Right Leg " },
}
for _, forms in ipairs(reset_limbs) do
  for i = 2, #forms do
    local limb, spelling = forms[1], forms[i]
    check("current-target reset accepts " .. spelling, function()
      local w, svo = boot()
      hit(w, "Ann", limb, 11); hit(w, "Bob", limb, 22)
      w.env.target = "  aNN  "
      svo.lc_reset(spelling)
      eq(svo.lc_list.Ann[limb], 0); eq(svo.lc_list.Bob[limb], 22)
    end)
    check("named limb reset accepts " .. spelling, function()
      local w, svo = boot()
      hit(w, "Ann", limb, 11); hit(w, "Bob", limb, 22)
      w.env.target = "Bob"
      svo.lc_reset("  aNN  " .. spelling .. "  ")
      eq(svo.lc_list.Ann[limb], 0); eq(svo.lc_list.Bob[limb], 22)
    end)
    check("explicit clearlimb accepts " .. spelling, function()
      local w, svo = boot()
      hit(w, "Ann", limb, 11); hit(w, "Bob", limb, 22)
      svo.lc_clearlimb("  aNN  ", spelling)
      eq(svo.lc_list.Ann[limb], 0); eq(svo.lc_list.Bob[limb], 22)
    end)
  end
end

check("named reset normalizes whitespace and case independently of the current target", function()
  local w, svo = boot()
  hit(w, "Ann", "head", 11); hit(w, "Bob", "head", 22)
  w.env.target = "Bob"
  svo.lc_reset("  aNN  ")
  eq(svo.lc_list.Ann, nil); eq(svo.lc_list.Bob.head, 22)
end)

check("invalid or missing targets never fall back to the last person hit", function()
  local w, svo = boot()
  hit(w, "Ann", "head", 11); hit(w, "Bob", "head", 22)
  local function unchanged()
    blank_tags(svo)
    svo.lc_reset(); svo.lc_reset(""); svo.lc_reset("h")
    eq(svo.lc_list.Ann.head, 11); eq(svo.lc_list.Bob.head, 22)
  end
  w.env.target = nil; unchanged()
  for _, value in ipairs({ "", "  ", "None", "none", "Dude", " dude ", "123", 123, false }) do
    w.env.target = value; unchanged()
  end
  w.env.target = "Cid"; unchanged()
  eq(svo.lc_list.Cid, nil)
end)

check("invalid multiword reset commands cannot mutate other people", function()
  local w, svo = boot()
  hit(w, "Ann", "head", 11); hit(w, "Bob", "head", 22)
  for _, command in ipairs({ "Bob tail", "Ann left ankle", "Bob left leg extra", "Ann Bob", "all head" }) do
    svo.lc_reset(command)
    eq(svo.lc_list.Ann.head, 11); eq(svo.lc_list.Bob.head, 22)
  end
  eq(svo.lc_list["Bob tail"], nil)
  svo.lc_clearlimb("Bob", "tail")
  svo.lc_clearlimb("None", "head")
  eq(svo.lc_list.Ann.head, 11); eq(svo.lc_list.Bob.head, 22)
end)

for level, raw in ipairs({ 0, 100, 200 }) do
  check("all prompt tags and vsl distinguish raw damage at level " .. level, function()
    local w, svo = boot()
    svo.lc_devastate("Ann", "legs", level); off_balance(w)
    hit(w, "Bob", "head", 19.7)
    w.env.target = "Ann"
    local reading = tostring(raw) .. "% [L" .. level .. "]"
    for _, text in ipairs(tags(svo)) do
      assert(plain(text):find(reading, 1, true), text)
      assert(not plain(text):find("19.7", 1, true), text)
    end
    w.echoes = {}; svo.lc_show()
    assert(said(w, "Ann")); assert(said(w, "Bob"))
    assert(said(w, "leftleg " .. reading))
    eq(svo.lc_list.Ann.leftleg, raw)
    eq(svo.lc_damage("Ann", "leftleg"), level == 1 and 100 or raw)
    eq(svo.lc_level("Ann", "leftleg"), level)
  end)
end

check("raw damage remains distinct from the combat accessor in stage-one hit echoes", function()
  local w, svo = boot()
  svo.lc_devastate("Ann", "legs", 1); off_balance(w)
  w.echoes = {}
  hit(w, "Ann", "left leg", 60)
  assert(said(w, "60% [L1]"))
  eq(svo.lc_list.Ann.leftleg, 60); eq(svo.lc_damage("Ann", "leftleg"), 100)
  hit(w, "Bob", "head", 19.7)
  w.env.target = "Ann"
  for _, text in ipairs(tags(svo)) do
    assert(plain(text):find("60% [L1]", 1, true), text)
    assert(not plain(text):find("100% [L1]", 1, true), text)
  end
  eq(svo.lc_damage("Ann", "leftleg"), 100)
end)

check("ordinary partial percentages have no stage-zero decoration", function()
  local w, svo = boot()
  hit(w, "Ann", "left leg", 8.4); hit(w, "Bob", "left leg", 19.7)
  w.env.target = "Ann"
  for _, text in ipairs(tags(svo)) do
    assert(plain(text):find("8.4%", 1, true), text)
    assert(not plain(text):find("[L0]", 1, true), text)
  end
  eq(svo.lc_list.Ann.leftleg, 8.4); eq(svo.lc_damage("Ann", "leftleg"), 8.4)
end)

check("reset command whitespace does not change its selected person or limb", function()
  local w, svo = boot()
  hit(w, "Ann", "left arm", 11); hit(w, "Ann", "head", 12)
  hit(w, "Bob", "left arm", 22)
  w.env.target = "Ann"
  svo.lc_reset("  LeFt   ArM  ")
  eq(svo.lc_list.Ann.leftarm, 0); eq(svo.lc_list.Ann.head, 12)
  eq(svo.lc_list.Bob.leftarm, 22)
  svo.lc_reset("   ")
  eq(svo.lc_list.Ann, nil); eq(svo.lc_list.Bob.leftarm, 22)
end)

check("marks itself as the percentage tracker", function()
  local _, svo = boot()
  eq(svo.lc_percent, true); eq(svo.lc_break_at, 100)
end)

if #failed == 0 then
  print(passed .. " checks, ALL PASS")
  os.exit(0)
end
print(passed .. " passed, " .. #failed .. " FAILED")
for _, f in ipairs(failed) do print("FAIL " .. f) end
os.exit(1)
