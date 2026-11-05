-- Run from Sources/svof: lua tools/test_prompt_literals.lua
-- Loads the real native compiler and prompt controller. Only Mudlet I/O and
-- Lua 5.2+'s missing loadstring environment boundary are adapted.
local world = dofile("tools/svof_world.lua")
local w = world.new({ class = "Runewarden" })
local s = w.svo
local checks = 0

local function eq(got, want, label)
  checks = checks + 1
  assert(got == want, label .. ": got " .. string.format("%q", tostring(got))
    .. ", wanted " .. string.format("%q", tostring(want)))
end

-- Mudlet's compiled prompt resolves svo in its profile environment, not in
-- this test process's globals. Keep that exact boundary on modern Lua too.
w.env.loadstring = function(code, name)
  if setfenv then
    local chunk, err = loadstring(code, name)
    if chunk then setfenv(chunk, w.env) end
    return chunk, err
  end
  return load(code, name, "t", w.env)
end
s.sk.logged_in = true
s.stats.currenthealth, s.stats.maxhealth = 4321, 5000
s.me.healthchange = -23

local function render(prompt, expected, label)
  s.conf.customprompt = prompt
  s.cp.makefunction()
  eq(s.cp.display(), expected, label)
  eq(s.conf.customprompt, prompt, label .. " does not migrate saved text")
end

render("Bob's @health", "Bob's 4321", "apostrophe adjacent to a native tag")
render([["quoted" 'single' \\ path\to\file \n \t \123]],
       [["quoted" 'single' \\ path\to\file \n \t \123]],
       "quotes and backslash sequences remain literal")
render("first\nsecond\r\nthird\t\000123\0019 @health!",
       "first\nsecond\r\nthird\t\000123\0019 4321!",
       "actual line breaks and control bytes survive encoding")
render("^r@healthh (^1@%health%) ^redok^w!",
       "<a_red>4321h (<a_darkgreen>86%) <red>ok<a_white>!",
       "native colours, named colour longest match and percent punctuation")
render("@diffhealth/@(diffhealth)/@[diffhealth] @unregistered ^unregistered",
       "-23/(-23)/[-23] @unregistered ^unregistered",
       "punctuation tags and unrecognised text")
render("", "", "empty prompt")

-- This was executable Lua when literal buffers were merely single-quoted.
local injection = "', (function() svo.me.prompt_literal_executed = true return 'owned' end)(), '"
render(injection, injection, "literal text cannot inject a compiled expression")
eq(s.me.prompt_literal_executed, nil, "literal injection was never executed")

-- adddefinition is intentionally a code-extension API, not another literal
-- input. Exercise both overlapping names and expressions returning user data.
s.me.prompt_literal_data = "Bob's \\\n@health ^r " .. injection
s.cp.adddefinition("@literal", "svo.me.prompt_literal_data")
s.cp.adddefinition("@literalmore", "svo.stats.currenthealth + 7")
s.cp.adddefinition("^extension", "'<magenta>'")
s.cp.adddefinition("!expr!", "(function() return 'expression works' end)()")
render("^extension@literalmore|@literal|!expr!",
       "<magenta>4328|" .. s.me.prompt_literal_data .. "|expression works",
       "registered expression extensions remain executable and longest-first")
eq(s.me.prompt_literal_executed, nil, "extension result is data, never recompiled")
s.me.prompt_literal_data = "changed 'data' \\ @%health"
eq(s.cp.display(), "<magenta>4328|" .. s.me.prompt_literal_data .. "|expression works",
   "compiled expressions read live data without re-parsing it")

-- Exercise the actual prompt controller's cecho consumer, not a second renderer.
s.conf.singleprompt = false
s.conf.showchanges = false
-- Feed the real GMCP stat consumer; paused curing sends no work.
w.env.gmcp.Char.Vitals = {
  hp = 4321, maxhp = 5000, mp = 5000, maxmp = 5000,
  ep = 20000, maxep = 20000, wp = 20000, maxwp = 20000,
}
s.conf.customprompt = "Bob's @health\n\\t ^r@%health%"
s.cp.makefunction()
local output = {}
w.env.cecho = function(text) output[#output + 1] = text end
s.onprompt()
eq(output[#output], "Bob's 4321\n\\t <a_red>86%", "native controller renders compiled prompt")
eq(s.me.prompt_literal_executed, nil, "controller did not execute literal text")

print("ALL PASS (" .. checks .. " prompt literal checks)")
