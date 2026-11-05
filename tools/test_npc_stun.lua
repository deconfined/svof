--[[
Native NPC stun onset regression. Run from the svof checkout:
  lua tools/test_npc_stun.lua

Loads all real svof subsystems through svof_world, then dispatches exact lines
through the generated native trigger catalog to the shipped static scripts.
Mudlet is stubbed; this is not a PCRE/Mudlet or live-game timing test.

The two Vertani sentences are the exact variants also recorded in LEVI's
722_Stunned.lua, not Foxhunt's unrestricted NPC/weapon captures. None of the
three new variants has a verified duration; native validation owns expiry.
]]

local world = dofile("tools/svof_world.lua")
local catalog = dofile("src/resources/trigger_catalog.lua")
local checks, failures = 0, {}
local function eq(actual, expected, label)
  checks = checks + 1
  if actual ~= expected then
    failures[#failures + 1] = string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual))
  end
end

local onsets = {
  { name = "Vertani headbutt",
    line = "Lunging at you, a scimitar-wielding Vertani soldier slams his gigantic head into yours. You are stunned from the blow." },
  { name = "Vertani weapon butt",
    line = "You gnash your teeth as a scimitar-wielding Vertani soldier brings the butt of his scimitar down on your head, splitting your skull." },
  { name = "Prison guard spear haft",
    line = "An off-duty prison guard pivots quickly and smashes the haft of his spear into the side of your head, making your ears ring." },
}
local recovery = { folder = "General", name = "svo stun wore off", line = "You are no longer stunned." }
local refusal = { folder = "General/Symptoms", name = "Stun", line = "You are too stunned to be able to do anything." }
local explosion = { folder = "Pranks", name = "Concussion bomb",
  line = "The explosion's concussion wave slams into you, stunning you momentarily." }


local function fresh(balanced, ai, paused)
  local w = world.new({ class = "Runewarden", paused = paused ~= false })
  local svo = w.svo
  svo.conf.aillusion = ai
  svo.bals.balance, svo.bals.equilibrium = balanced, balanced
  w.stun_adds, w.stun_waits = 0, 0
  local addaffdict, doaction = svo.addaffdict, svo.doaction
  svo.addaffdict = function(entry, ...)
    if entry == svo.dict.stun then w.stun_adds = w.stun_adds + 1 end
    return addaffdict(entry, ...)
  end
  svo.doaction = function(entry, ...)
    if entry == svo.dict.stun.waitingfor then w.stun_waits = w.stun_waits + 1 end
    return doaction(entry, ...)
  end
  return w
end
local function feed(w, t)
  w.line(t.line)
  w.env.matches = { t.line }
  for _, folder in ipairs(catalog) do
    for i = 2, #folder do
      local trigger = folder[i]
      for j = 2, #trigger do
        if trigger[j][1] == "exact" and trigger[j][2] == t.line then
          local path = "src/triggers/" .. folder[1]:gsub(" / ", "/") .. "/"
            .. trigger[1]:gsub(" ", "_") .. ".lua"
          w.run(world.read_file(path), path)
          break
        end
      end
    end
  end
end
local function settled(w, label)
  eq(w.svo.affs.stun, nil, label .. " affliction cleared")
  eq(w.svo.affl.stun, nil, label .. " public affliction cleared")
  eq(w.svo.actions.stun_waitingfor, nil, label .. " waiting action cleared")
  eq(w.svo.affsp.stun, nil, label .. " no pending stun suspicion")
end
local function expire(w)
  local action = assert(w.svo.actions.stun_waitingfor, "native stun waiting action missing")
  local timer = assert(w.timers[action.timerid], "native stun waiting timer missing")
  w.advance(timer.at - w.now + .01)
end
local function accepted_paragraph(w, t)
  feed(w, t)
  -- Native proper_stun's AI accepts a paragraph longer than two lines. Do
  -- not bypass its check by adding the affliction or invoking oncompleted.
  w.line("A harmless additional combat line.")
  w.line("Another harmless additional combat line.")
  w.prompt()
end

for _, balanced in ipairs({ true, false }) do
  for _, t in ipairs(onsets) do
    local label = t.name .. (balanced and " balanced" or " off balance")
    -- With AI off, every onset is still a lifevision claim, not an immediate
    -- out-of-band flag; attack balance never controls incoming stuns.
    local w = fresh(balanced, false)
    feed(w, t)
    eq(w.svo.affs.stun, nil, label .. " waits for native validation")
    w.prompt()
    eq(w.svo.affs.stun ~= nil, true, label .. " onset recorded")
    eq(w.svo.affl.stun ~= nil, true, label .. " public state recorded")
    eq(w.stun_adds, 1, label .. " added once")
    eq(w.stun_waits, 1, label .. " one native waiting action")
    local timerid = w.svo.actions.stun_waitingfor.timerid
    feed(w, t)
    w.prompt()
    eq(w.stun_adds, 1, label .. " repeated onset does not add again")
    eq(w.stun_waits, 1, label .. " repeated onset does not restart expiry")
    eq(w.svo.actions.stun_waitingfor.timerid, timerid, label .. " native timer retained")
    feed(w, recovery)
    w.prompt()
    settled(w, label .. " recovery")
    eq(w.timers[timerid], nil, label .. " recovery kills native timer")
    w.advance(10)
    eq(w.stun_adds, 1, label .. " no delayed re-add after recovery")

    local timed = fresh(balanced, false)
    feed(timed, t)
    timed.prompt()
    expire(timed)
    settled(timed, label .. " native timeout")

    -- Accepted and explicitly rejected claims pass through native validation.
    local accepted = fresh(balanced, true)
    accepted_paragraph(accepted, t)
    eq(accepted.svo.affs.stun ~= nil, true, label .. " AI accepts real paragraph")
    eq(accepted.stun_adds, 1, label .. " accepted claim processed once")
    feed(accepted, recovery)
    accepted.prompt()
    settled(accepted, label .. " AI recovery")

    local rejected = fresh(balanced, true)
    feed(rejected, t)
    rejected.svo.sys.flawedillusion = true
    rejected.prompt()
    settled(rejected, label .. " rejected illusion")
    eq(rejected.stun_adds, 0, label .. " rejected claim never added")
    eq(rejected.stun_waits, 0, label .. " rejected claim starts no timeout")
    eq(rejected.svo.actions.stun_aff, nil, label .. " rejected direct claim removed")
    eq(rejected.svo.actions.checkstun_aff, nil, label .. " rejected probe claim removed")
  end
end

-- A short onset paragraph uses the existing probe/refusal lifecycle when
-- curing is running. Exercise both native confirmation and recovery before
-- the probe answers, with our attack balances up and down.
for _, balanced in ipairs({ true, false }) do
  for _, t in ipairs(onsets) do
    local w = fresh(balanced, true, false)
    feed(w, t)
    w.prompt()
    eq(w.svo.affs.stun, nil, "short paragraph is not prematurely confirmed")
    eq(w.svo.affsp.stun, true, "native stun suspicion recorded")
    eq(w.svo.actions.checkstun_misc ~= nil, true, "native probe started")
    feed(w, refusal)
    w.prompt()
    w.advance(0)
    eq(w.svo.affs.stun ~= nil, true, "existing refusal confirms native probe")
    eq(w.stun_adds, 1, "probe confirmation adds once")
    eq(w.stun_waits, 1, "probe confirmation starts one native timeout")
    eq(w.svo.affsp.stun, nil, "confirmed suspicion removed")
    eq(w.svo.dict.checkstun.templifevision, nil, "confirmed paragraph restored")
    eq(w.svo.dict.checkstun.tempactions, nil, "confirmed action snapshot released")
    expire(w)
    settled(w, "confirmed probe timeout")

    local recovered = fresh(balanced, true, false)
    feed(recovered, t)
    recovered.prompt()
    feed(recovered, recovery)
    recovered.prompt()
    recovered.advance(0)
    settled(recovered, "recovery before probe confirmation")
    eq(recovered.stun_adds, 0, "early recovery does not invent confirmed stun")
    eq(recovered.svo.actions.checkstun_misc, nil, "early recovery finishes probe")
    eq(recovered.svo.dict.checkstun.templifevision, nil, "early recovery restores paragraph")
    eq(recovered.svo.dict.checkstun.tempactions, nil, "early recovery releases action snapshot")
  end
end

-- Existing generic sources retain their sole native handlers; these changes
-- add no second refusal, recovery or explosion observer.
for _, t in ipairs({ refusal, explosion }) do
  local w = fresh(true, false)
  feed(w, t)
  w.prompt()
  eq(w.stun_adds, 1, t.name .. " existing handler adds once")
  eq(w.stun_waits, 1, t.name .. " existing handler has one timeout")
  feed(w, recovery)
  w.prompt()
  settled(w, t.name .. " existing recovery")
end

print(string.format("%d checks, %d failures", checks, #failures))
if #failures > 0 then
  for _, failure in ipairs(failures) do print("FAIL: " .. failure) end
  os.exit(1)
end
print("ALL PASS")
