-- Native warning/action/lifevision regressions; only Mudlet I/O is stubbed.
-- Run from Sources/svof: lua tools/test_hazard_warnings.lua
-- tools/test_passive_observations.py optionally supplies real-PCRE captures.
local world = dofile("tools/svof_world.lua")
local root = "src/triggers/svo (aliases, triggers)/svo/"
local cases = {
  {group="Miscellaneous", name="Endbringer start", captures={"ReciterA", "ListenerA"}, tokens={"ReciterA", "ListenerA", "Endbringer"}},
  {group="Miscellaneous", name="Endbringer continuation", captures={"ReciterB", "ListenerB"}, tokens={"ReciterB", "ListenerB", "Endbringer"}, absent={"ReciterA", "ListenerA"}},
  {group="Ignition", name="Incandescence start", captures={"FlameA"}, tokens={"FlameA", "Incandescence"}},
  {group="Ignition", name="Incandescence activation", captures={"FlameB"}, tokens={"FlameB", "incandescent"}},
  {group="Ignition", name="Incandescence room", captures={"FlameC", "MiddleProse", "FlameD"}, tokens={"Incandescence"}, absent={"FlameC", "FlameD", "MiddleProse"}},
  {group="Miscellaneous", name="Criers bell start", captures={"BellA"}, tokens={"BellA", "bell"}, absent={"you"}},
  {group="Miscellaneous", name="Criers bell direct", captures={"BellB"}, tokens={"BellB", "bell", "you"}},
  {group="Duress", name="Rising winds", captures={}, tokens={"Wind", "thunder"}, absent={"StaleActor"}},
  {group="Duress", name="Upward launch", captures={}, tokens={"air", "upward"}, absent={"StaleActor"}},
  {group="Duress", name="Resounding clap", captures={"AirA"}, tokens={"AirA", "clap"}, absent={"you", "dead", "pressure"}},
}
local supplied = arg[1] and dofile(arg[1])
if supplied then cases = supplied.hazards end
local checks = 0
local function check(value, label)
  checks = checks + 1
  assert(value, label)
end
local function output(w) return table.concat(w.echoes, "") end
local function count(text, needle)
  local n, at = 0, 1
  while true do
    local found = text:find(needle, at, true)
    if not found then return n end
    n, at = n + 1, found + #needle
  end
end
local function fixture()
  local w = world.new({class="Runewarden"})
  w.svo.logging_in = false
  w.svo.conf.aillusion, w.svo.conf.batch = false, false
  w.advance(0)
  w.echoes, w.sent, w.links = {}, {}, {}
  return w
end
local function prompt(w)
  w.env.line = "prompt"
  w.svo.onprompt()
  w.advance(0)
  for _, link in ipairs(w.links) do
    check(not link:find("(e!)", 1, true), "native prompt/handler error: "..link)
  end
end
local function observe(w, case)
  local path = case.path or root..case.group.."/"..case.name:gsub(" ", "_")..".lua"
  w.env.line = case.line or case.name
  w.svo.paragraph_length = w.svo.paragraph_length + 1
  -- Poison before replacing captures: captureless observations must ignore old
  -- actor evidence, even when Mudlet leaves it accessible in matches[2].
  w.env.matches = {w.env.line, "StaleActor", "StaleListener", "StaleTail"}
  if case.matches then
    for i, value in ipairs(case.matches) do w.env.matches[i] = value end
  else
    for i, value in ipairs(case.captures) do w.env.matches[i + 1] = value end
  end
  w.run(world.read_file(path), path)
end
local function check_case(text, case)
  for _, token in ipairs(case.tokens) do check(text:find(token, 1, true), case.name..": missing "..token) end
  for _, token in ipairs(case.absent or {}) do check(not text:find(token, 1, true), case.name..": invented "..token) end
end

for _, case in ipairs(cases) do
  local w = fixture()
  local triggers = #w.triggers
  observe(w, case)
  check(count(output(w), "Careful:") == 0, case.name..": not printed before acceptance")
  prompt(w)
  check(count(output(w), "Careful:") == 1, case.name..": prints once")
  check_case(output(w), case)
  check(#w.triggers == triggers, case.name..": initial-only, no prefix trigger")
  prompt(w)
  check(count(output(w), "Careful:") == 1, case.name..": no next-prompt replay")
  check(#w.sent == 0, case.name..": passive observer sends nothing")
end

-- Accepted concurrent observations are all rendered, in observation order.
do
  local w = fixture()
  for _, case in ipairs(cases) do observe(w, case) end
  prompt(w)
  local text, at = output(w), 1
  check(count(text, "Careful:") == #cases, "all concurrent warnings survive one lifevision key")
  for _, case in ipairs(cases) do
    local found = text:find(case.tokens[1], at, true)
    check(found, case.name..": ordered observation")
    at = found + #case.tokens[1]
  end
  prompt(w)
  check(count(output(w), "Careful:") == #cases, "concurrent batch not replayed")
end
do
  local w = fixture()
  w.svo.conf.aillusion, w.svo.conf.batch = true, true
  for _, case in ipairs(cases) do observe(w, case) end
  prompt(w)
  check(count(output(w), "Careful:") == #cases, "native batch mode accepts concurrent single-line warnings")
end

-- Rejected paragraphs cannot leave a side queue to donate to a later warning.
for _, rejection in ipairs({"flawed", "lineguard"}) do
  local w = fixture()
  w.svo.conf.aillusion = true
  for _, case in ipairs(cases) do observe(w, case) end
  if rejection == "flawed" then w.svo.sys.flawedillusion = true end
  prompt(w)
  check(count(output(w), "Careful:") == 0, rejection..": rejected batch silent")
  observe(w, cases[1])
  prompt(w)
  check(count(output(w), "Careful:") == 1, rejection..": fresh warning only")
  check(not output(w):find("ListenerB", 1, true), rejection..": rejected identities do not leak")
end

-- Real timed native action expiry followed by a fresh observation must not
-- revive the expired claim. checkaction-based ordinary warnings have no timer.
do
  local w = fixture()
  -- givewarning is normally observation-only (checkaction, no timer). Supply
  -- a harmless start for this timed-action input while retaining the real
  -- warning completion, expiry and lifevision code.
  local timed = {}
  for key, value in pairs(w.svo.dict.givewarning.happened) do timed[key] = value end
  timed.onstart = function() end
  w.svo.doaction(timed)
  observe(w, cases[2])
  w.advance(100)
  w.echoes, w.links = {}, {}
  prompt(w)
  check(count(output(w), "Careful:") == 0, "expired warning silent at the next prompt")
  observe(w, cases[1])
  prompt(w)
  check(count(output(w), "Careful:") == 1, "expired action contributes no old warnings")
  check(not output(w):find("ListenerB", 1, true), "expired identity not replayed")
end

-- Reload the actual controller source, not extracted warning functions.
for _, boundary in ipairs({"reload", "disconnect", "relogin"}) do
  local w = fixture()
  observe(w, cases[2])
  if boundary == "reload" then
    local path = "src/scripts/svo (curing skeleton, controllers, action system)/Controllers.lua"
    w.run(world.read_file(path), path)
    w.svo.loader.controllers()
  elseif boundary == "disconnect" then
    for _, handler in ipairs(w.handlers) do
      if handler.name == "sysDisconnectionEvent" and not handler.killed then handler.f() end
    end
  else w.svo.signals.relogin:emit() end
  w.echoes, w.links = {}, {}
  prompt(w)
  check(count(output(w), "Careful:") == 0, boundary..": pending warning discarded")
  observe(w, cases[1])
  prompt(w)
  check(count(output(w), "Careful:") == 1, boundary..": fresh warning still accepted")
  check(not output(w):find("ListenerB", 1, true), boundary..": no old identity")
end

-- Preserve the public single/multi callers and the native delayed prefix.
for _, mode in ipairs({false, "all", "prompt", "right"}) do
  local w = fixture()
  w.svo.conf.warningtype = mode
  w.svo.givewarning({initialmsg="LegacySingle"})
  w.svo.givewarning_multi({initialmsg="LegacyMulti", prefixwarning="LegacyPrefix", startin=2, duration=3})
  prompt(w)
  check(count(output(w), "LegacySingle") == 1, tostring(mode)..": legacy single")
  check(count(output(w), "LegacyMulti") == 1, tostring(mode)..": legacy multi")
  check(not w.svo.cnrl.warnids.LegacyPrefix, tostring(mode)..": prefix waits for start")
  if mode then
    w.advance(2)
    local id = w.svo.cnrl.warnids.LegacyPrefix
    check(id and not w.triggers[id].killed, tostring(mode)..": prefix starts after delay")
    w.env.line = "ordinary line"
    w.env.isPrompt = function() return false end
    local before = count(output(w), "LegacyPrefix")
    w.run(w.triggers[id].code)
    check(count(output(w), "LegacyPrefix") == before + (mode == "prompt" and 0 or 1), tostring(mode)..": native prefix mode")
    w.env.isPrompt = function() return true end
    w.run(w.triggers[id].code)
    check(count(output(w), "LegacyPrefix") > before, tostring(mode)..": prompt prefix rendered")
    w.advance(3)
    check(w.triggers[id].killed, tostring(mode)..": prefix expires at original interval")
  end
end

-- One accepted batch owns one prefix: the last prefixed record, even when an
-- initial-only hazard follows it. Exercise native start/end timers and every
-- live prefix trigger so duplicate triggers cannot hide behind a chosen ID.
do
  local w = fixture()
  w.svo.conf.warningtype = "all"
  local triggers = #w.triggers
  w.svo.givewarning_multi({initialmsg="FirstInitial", prefixwarning="FirstPrefix", startin=1, duration=6})
  w.svo.givewarning_multi({initialmsg="ChosenInitial", prefixwarning="ChosenPrefix", startin=2, duration=2})
  observe(w, cases[1])
  check(count(output(w), "Careful:") == 0, "mixed prefixes wait for native acceptance")
  prompt(w)
  local text = output(w)
  check(count(text, "Careful:") == 3, "mixed prefix batch renders every initial once")
  check(count(text, "FirstInitial") == 1 and count(text, "ChosenInitial") == 1,
    "both prefixed records retain their initial messages")
  check_case(text, cases[1])
  local first = text:find("FirstInitial", 1, true)
  local chosen = text:find("ChosenInitial", 1, true)
  local hazard = text:find(cases[1].tokens[1], 1, true)
  check(first and chosen and hazard and first < chosen and chosen < hazard,
    "mixed prefix batch preserves accepted initial order")
  check(w.svo.cnrl.warning == "ChosenPrefix", "following initial-only hazard keeps last prefix identity")
  local function fire_prefixes()
    w.env.line = "ordinary line"
    w.env.isPrompt = function() return false end
    for i = triggers + 1, #w.triggers do
      local trigger = w.triggers[i]
      if not trigger.killed and trigger.kind == "regex" and trigger.pattern == "^" then
        w.run(trigger.code)
      end
    end
  end
  w.advance(1)
  fire_prefixes()
  check(not w.svo.cnrl.warnids.FirstPrefix, "earlier prefix is never scheduled")
  check(count(output(w), "ChosenPrefix") == 0, "chosen prefix retains its own start delay")
  w.advance(1)
  local id = w.svo.cnrl.warnids.ChosenPrefix
  check(id and not w.triggers[id].killed, "chosen native prefix starts on time")
  check(#w.triggers == triggers + 1, "exactly one native prefix trigger created")
  fire_prefixes()
  check(count(output(w), "ChosenPrefix") == 1, "one chosen prefix rendered per matching line")
  check(count(output(w), "FirstPrefix") == 0, "unchosen prefix never renders")
  w.advance(1)
  fire_prefixes()
  check(count(output(w), "ChosenPrefix") == 2, "chosen prefix remains active during its duration")
  w.advance(1)
  check(w.triggers[id].killed, "chosen prefix expires at its own native deadline")
  fire_prefixes()
  check(count(output(w), "ChosenPrefix") == 2, "no prefix survives chosen expiry before earlier deadline")
  w.advance(3)
  fire_prefixes()
  check(count(output(w), "ChosenPrefix") == 2, "earlier prefix duration cannot replay chosen identity")
  prompt(w)
  check(count(output(w), "Careful:") == 3, "mixed prefix batch never replays initial messages")
  check(#w.sent == 0, "mixed prefix batch remains passive")
end

-- Optional integration fixture: Python matched the actual shipped metadata
-- with PCRE2/substring semantics; run its resulting captures through the real
-- static scripts and native state, never the world's regex approximation.
if supplied and supplied.priority then
  local w = fixture()
  local s = w.svo
  local function ranks()
    local entries = {}
    for aff, item in pairs(s.dict) do
      if type(item) == "table" then
        for balance, action in pairs(item) do
          if type(action) == "table" then
            entries[#entries + 1] = aff..":"..tostring(balance)..":"..tostring(action.aspriority)..":"..tostring(action.spriority)
          end
        end
      end
    end
    table.sort(entries)
    return table.concat(entries, "|")
  end
  local before = ranks()
  for _, case in ipairs(supplied.priority) do
    w.env.matches = {"poison", "StaleAffliction"}
    for i, value in ipairs(case.matches) do w.env.matches[i] = value end
    w.env.line = case.line
    w.run(world.read_file(case.path), case.path)
    check(s.me.priorityaff.status == case.status, case.name..": observed status")
    check(s.me.priorityaff.affliction == case.affliction, case.name..": raw observed name")
    check(ranks() == before, case.name..": rank tables unchanged")
    check(#w.sent == 0, case.name..": no commands")
  end
  prompt(w)
  check(#w.sent == 0, "feedback remains passive at native prompt")
end
print("ALL PASS: hazard warnings ("..checks.." checks; "..#cases.." observation fixtures)")
