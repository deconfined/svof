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
  * nn, vsl and the three prompt tags work on percentages.
  * running the loader again, as a class change does, doesn't double a hit.

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

check("a limb broken with no damage shows as broken everywhere it's read", function()
  local w, svo = boot()
  devastate(w, "legs", 1)
  assert(said(w, "Bob's leftleg is broken at 100%."))
  assert(svo.lc_prompttag2():find("ll 100", 1, true))
  assert(svo.lc_prompttag():find("<a_red>100", 1, true))
  svo.lc_show()
  assert(said(w, "leftleg 100%"))
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

check("announces progress, a prepped limb and a break", function()
  local w = boot()
  hit(w, "Bob", "head", 30)
  assert(said(w, "Bob's head is now at 30%."))
  hit(w, "Bob", "head", 40)
  assert(said(w, "Bob's head is prepped at 70%."))
  hit(w, "Bob", "head", 40)
  assert(said(w, "Bob's head is broken at 110%."))
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

check("names other prepped limbs", function()
  local w = boot()
  hit(w, "Bob", "head", 70); hit(w, "Bob", "torso", 70)
  assert(said(w, "Their head is also prepped."))
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

check("nn resets the last person hit", function()
  local w, svo = boot()
  hit(w, "Ann", "head", 10); hit(w, "Bob", "head", 10)
  svo.lc_reset()
  eq(svo.lc_list.Bob, nil); eq(svo.lc_list.Ann.head, 10)
end)

check("nn with an empty capture is the same", function()
  local w, svo = boot()
  hit(w, "Bob", "head", 10)
  svo.lc_reset("")
  eq(svo.lc_list.Bob, nil)
end)

check("nn <limb> resets one limb of the last person hit", function()
  local w, svo = boot()
  hit(w, "Bob", "left leg", 10); hit(w, "Bob", "head", 10)
  svo.lc_reset("ll")
  eq(svo.lc_list.Bob.leftleg, 0); eq(svo.lc_list.Bob.head, 10)
end)

check("nn <person> and nn all", function()
  local w, svo = boot()
  hit(w, "Ann", "head", 10); hit(w, "Bob", "head", 10); hit(w, "Cid", "head", 10)
  svo.lc_reset("ann")
  eq(svo.lc_list.Ann, nil); eq(svo.lc_list.Bob.head, 10)
  svo.lc_reset("all")
  eq(next(svo.lc_list), nil)
end)

check("nn with nobody tracked says so instead of erroring", function()
  local w, svo = boot()
  svo.lc_reset(); svo.lc_reset("ll"); svo.lc_reset("Nobody")
  assert(said(w, "Not keeping track of anyone to reset them anyway."))
  assert(said(w, "Not keeping track of anyone yet to reset their limb."))
  assert(said(w, "Weren't keeping track of Nobody anyway."))
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

check("vsl shows percentages", function()
  local w, svo = boot()
  svo.lc_show()
  assert(said(w, "Not keeping track of anyone yet."))
  hit(w, "Bob", "head", 8.9)
  svo.lc_show()
  assert(said(w, "head 8.9%"))
end)

check("the prompt tags are empty with nobody hit, then show percentages", function()
  local w, svo = boot()
  eq(svo.lc_prompttag(), ""); eq(svo.lc_prompttag2(), ""); eq(svo.lc_prompttag3(), "")
  hit(w, "Bob", "left leg", 8.4)
  eq(svo.lc_prompttag2(), "Bob: h 0|t 0|ra 0|la 0|rl 0|ll 8.4")
  assert(svo.lc_prompttag():find("8.4", 1, true))
  assert(svo.lc_prompttag3():find("8.4", 1, true))
end)

check("the prompt tags go red on a broken or prepped limb", function()
  local w, svo = boot()
  hit(w, "Bob", "left arm", 10)
  assert(not svo.lc_prompttag():find("<a_red>10", 1, true))
  hit(w, "Bob", "left arm", 95)
  assert(svo.lc_prompttag():find("<a_red>105", 1, true))
end)

check("running the loader again doesn't double a hit", function()
  local w, svo = boot()
  svo.loader.limbcounter(); svo.loader.limbcounter()
  hit(w, "Bob", "head", 10)
  eq(svo.lc_list.Bob.head, 10)
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
