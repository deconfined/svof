--[[
Consumer regressions for focus guards, using the complete native svof loaders.
Only Mudlet I/O is stubbed by svof_world; focus selection, the impatience probe,
login policy delivery, priority lifecycle and balance recovery are real source.

Run from Sources/svof: lua tools/test_focus_guards.lua
Exits 0 and prints "ALL PASS" on success, exits 1 and prints failures.
]]

local world = dofile("tools/svof_world.lua")
local checks, failures = 0, 0
local function check(desc, got, want)
  checks = checks + 1
  if got ~= want then
    failures = failures + 1
    print(string.format("FAIL %s: got %s, want %s", desc, tostring(got), tostring(want)))
  end
end

local function fixture()
  local w = world.new({class = "Runewarden"})
  local s = w.svo
  s.logging_in = false
  s.conf.serverside, s.conf.keepup, s.conf.focus = false, false, true
  s.conf.focuswithcadmus, s.conf.focuswithfulminated, s.conf.focuswithguilt = false, false, false
  s.stats.currentmana, s.stats.currentwillpower, s.stats.wp = 1000, 1000, 100
  s.sys.manause = 0
  w.advance(0)
  w.sent = {}
  return w
end

-- Decode the native transport at the game boundary, not its queue layout or
-- echo flags. Alias definitions alone do not execute their bodies.
local function commands(w)
  local result, aliases = {}, {}
  local consume
  consume = function(command)
    local alias, body = command:match("^setalias (%w+) (.*)$")
    if alias then aliases[alias] = body; return end
    if aliases[command] then consume(aliases[command]); return end
    if command:match("^9multicmd ") then
      for part in command:gmatch("{([^}]*)}") do consume(part) end
    elseif command:find("/", 1, true) then
      for part in command:gmatch("[^/]+") do consume(part) end
    else
      result[#result + 1] = command
    end
  end
  for _, command in ipairs(w.sent) do consume(command) end
  return result
end

local function count_command(w, wanted)
  local count = 0
  for _, command in ipairs(commands(w)) do
    if command == wanted then count = count + 1 end
  end
  return count
end

local guards = {
  {'cadmus', 'focuswithcadmus'},
  {'fulminated', 'focuswithfulminated'},
  {'guilt', 'focuswithguilt'},
}

-- Exercise the real selector and action sender rather than the helper's
-- implementation. Cadmus's per-affliction permission is explicit test input.
for _, case in ipairs(guards) do
  local aff, option = case[1], case[2]
  local w = fixture()
  local s = w.svo
  s.me.cadmusaffs.stupidity = true
  s.addaffdict(s.dict.stupidity)
  s.addaffdict(s.dict[aff])
  check(aff .. ": disabled preference rejects focus admission", s.check_focus(true), nil)
  s.check_focus()
  check(aff .. ": disabled preference sends no focus", count_command(w, "focus"), 0)
  s.conf[option] = true
  check(aff .. ": enabled preference admits a focus cure", s.check_focus(true) ~= nil, true)
  s.check_focus()
  check(aff .. ": enabled preference sends focus", count_command(w, "focus"), 1)
end

do
  local w = fixture()
  local s = w.svo
  s.addaffdict(s.dict.stupidity)
  s.check_focus()
  check("stupidity without a harmful affliction sends focus", count_command(w, "focus"), 1)
end

do
  local w = fixture()
  local s = w.svo
  s.addaffdict(s.dict.stupidity)
  s.addaffdict(s.dict.cadmus)
  s.conf.focuswithcadmus = true
  s.me.cadmusaffs.stupidity = false
  check("cadmus still requires permission for the cure", s.check_focus(true), nil)
  s.check_focus()
  check("cadmus without per-cure permission sends no focus", count_command(w, "focus"), 0)
end

-- The native miscellaneous-action consumer must respect the same preferences
-- before the impatience probe's bare focus is allowed onto the wire.
for _, case in ipairs(guards) do
  local aff, option = case[1], case[2]
  local w = fixture()
  local s = w.svo
  s.affsp.impatience = true
  s.addaffdict(s.dict[aff])
  check("probe: " .. aff .. " blocks admission", s.dict.checkimpatience.misc.isadvisable(), false)
  s.check_misc()
  check("probe: " .. aff .. " sends no focus while blocked", count_command(w, "focus"), 0)
  s.conf[option] = true
  check("probe: " .. option .. " admits the probe", s.dict.checkimpatience.misc.isadvisable(), true)
  s.check_misc()
  check("probe: " .. option .. " permits the bare focus", count_command(w, "focus"), 1)
end

do
  local w = fixture()
  local s = w.svo
  s.check_misc()
  check("probe: no suspicion sends no focus", count_command(w, "focus"), 0)
  s.affsp.impatience = true
  s.conf.focus = false
  check("probe: focus disabled rejects admission", s.dict.checkimpatience.misc.isadvisable(), false)
  s.conf.focus, s.bals.focus = true, false
  check("probe: missing focus balance rejects admission", s.dict.checkimpatience.misc.isadvisable(), false)
  s.bals.focus = true
  s.addaffdict(s.dict.sleep)
  check("probe: sleep rejects admission", s.dict.checkimpatience.misc.isadvisable(), false)
  s.rmaff('sleep')
  s.check_misc()
  check("probe: suspicion without a blocker sends focus", count_command(w, "focus"), 1)
end

-- Native login signals and the welcome-line trigger deliver each explicitly
-- chosen policy. No fake sendfocuswith/resumepriorityupdates helper is needed;
-- the same login also lets the native priority snapshot reach the transport.
for _, serverside in ipairs({true, false}) do
  for _, fulminated in ipairs({true, false}) do
    for _, guilt in ipairs({true, false}) do
      local w = fixture()
      local s = w.svo
      s.conf.serverside = serverside
      s.conf.focuswithfulminated, s.conf.focuswithguilt = fulminated, guilt
      s.setup_default_serverignore()
      s.logging_in, s.dont_unpause_login = true, true
      w.env.gmcp.Char.Name = {name = "FocusTester"}
      s.signals.gmcpcharname:emit()
      w.line("Password correct. Welcome to Achaea.")
      w.advance(0)
      for _ = 1, 10 do w.advance(2) end
      local label = "login serverside=" .. tostring(serverside)
        .. " fulminated=" .. tostring(fulminated) .. " guilt=" .. tostring(guilt)
      for _, policy in ipairs({{'fulminated', fulminated}, {'guilt', guilt}}) do
        local aff, enabled = policy[1], policy[2]
        check(label .. ": selected " .. aff .. " switch", count_command(w,
          "curing focus " .. (enabled and "with" or "without") .. aff), serverside and 1 or 0)
        check(label .. ": opposite " .. aff .. " switch absent", count_command(w,
          "curing focus " .. (enabled and "without" or "with") .. aff), 0)
      end
      local priorities = false
      for _, command in ipairs(commands(w)) do
        if command:match("^curing priority %S+ %S+") then priorities = true end
      end
      check(label .. ": native priorities reach the game only when enabled", priorities, serverside)
    end
  end
end

-- Check the balance consumer on both sides of the recovery deadline, not the
-- timer registration or source table. The host's callbacks remain untouched.
local function recovery(label, held, latency, cured, expected)
  local w = fixture()
  local s = w.svo
  for _, aff in ipairs(held) do s.addaffdict(s.dict[aff]) end
  s.conf.ai_resetfocusbal = 5
  w.env.getNetworkLatency = function() return latency end
  s.lostbal_focus(cured)
  check(label .. ": focus balance is lost", s.bals.focus, false)
  w.advance(expected - 0.01)
  check(label .. ": focus cannot recover early", s.bals.focus, false)
  w.advance(0.02)
  check(label .. ": focus recovers after deadline", s.bals.focus, true)
end

recovery("ordinary focus", {}, 2, 'stupidity', 5)
recovery("madness with little lag", {'madness'}, 0.3, 'stupidity', 5)
recovery("rixil preserves its longer delay", {'madness', 'rixil'}, 0.3, 'stupidity', 8)
for _, aff in ipairs({
  'addiction', 'agoraphobia', 'confusion', 'dementia', 'hallucinations',
  'hypersomnia', 'impatience', 'loneliness', 'lovers', 'masochism',
  'paranoia', 'recklessness', 'stupidity',
}) do
  recovery("madness after curing " .. aff, {'madness'}, 2, aff, 6)
end
recovery("madness after dizziness", {'madness'}, 2, 'dizziness', 5)
recovery("madness after vertigo", {'madness'}, 2, 'vertigo', 5)
recovery("madness after an unknown cure", {'madness'}, 2, nil, 6)
recovery("madness caps a latency spike", {'madness'}, 9.9, 'paranoia', 7)

print(string.format("%d checks, %d failures", checks, failures))
if failures > 0 then print("FAILED") os.exit(1) end
print("ALL PASS")
