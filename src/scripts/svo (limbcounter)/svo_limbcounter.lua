-- Svof (c) 2011-2018 by Vadim Peretokin
-- Svof is licensed under a
-- Creative Commons Attribution-NonCommercial-ShareAlike 4.0 International License.
-- You should have received a copy of the license along with this
-- work. If not, see <http://creativecommons.org/licenses/by-nc-sa/4.0/>.

-- Tracks the limb damage you deal, from the percentage the game prints with each hit.
-- A limb breaks at 100 and damage keeps adding up past that. Its level says what it takes
-- to heal, one salve to a level:
--   1: broken, with no damage behind it. Mending cures it.
--   2: damaged, from 100. Restoration takes the damage away, which leaves level 1.
--   3: mangled, from 200. Restoration takes it to level 2.
-- Head and torso have no bones to mend, so restoration heals them outright from level 2.
-- A limb also clears after svo.lc_forget_after seconds without a hit.

svo.loader.limbcounter = function()
local limbs = {'head', 'torso', 'rightarm', 'leftarm', 'rightleg', 'leftleg'}
local short = {h = 'head', t = 'torso', rl = 'rightleg', ll = 'leftleg', ra = 'rightarm', la = 'leftarm',
  ['left arm'] = 'leftarm', ['right arm'] = 'rightarm', ['left leg'] = 'leftleg', ['right leg'] = 'rightleg'}
local limb_area = {head = 'head', torso = 'torso', leftarm = 'arms', rightarm = 'arms',
  leftleg = 'legs', rightleg = 'legs'}
-- what a salve line can name, in the order a cure takes the limbs
local salved = {
  head = {'head'}, torso = {'torso'}, body = {'torso'},
  arms = {'leftarm', 'rightarm'}, legs = {'leftleg', 'rightleg'},
}

-- what mending can reach
local bones = {arms = salved.arms, legs = salved.legs}

-- what DEVASTATE strikes
local devastated = {arms = {'leftarm', 'rightarm'}, legs = {'leftleg', 'rightleg'}}

-- Keep ownership across loader/class changes; existing timers retain their deadlines.
-- The first upgrade from the old closure-local tracker requires a client restart: those
-- inaccessible timers cannot be safely recovered or cancelled.
svo._lc_runtime = svo._lc_runtime or {pending = {}, forget = {}, cures = {}, lastdamage = {}}
local runtime = svo._lc_runtime
local forget, cures, lastdamage = runtime.forget, runtime.cures, runtime.lastdamage

svo.lc_percent = true
svo.lc_list = svo.lc_list or {}
svo.lc_levels = svo.lc_levels or {}
svo.lc_lasthit = svo.lc_lasthit or ""
svo.lc_break_at = 100
svo.lc_forget_after = svo.lc_forget_after or 180
-- Restoration lands at 4 seconds, as its salve balance comes back, so the person's next salve
-- can reach us at the same moment. This stays ahead of that line.
svo.lc_cure_delay = svo.lc_cure_delay or 3.7

local levels = svo.lc_levels

local function player_name(who)
  if type(who) ~= "string" then return end
  who = who:match("^%s*([%a]+)%s*$")
  if not who then return end
  who = who:lower()
  if who == "none" or who == "dude" then return end
  return who:sub(1, 1):upper() .. who:sub(2)
end

local function limb_name(where)
  if type(where) ~= "string" then return end
  where = where:lower():match("^%s*(.-)%s*$"):gsub("%s+", " ")
  where = short[where] or where
  return limb_area[where] and where
end

-- Also invalidate a batch already being consumed if an event handler resets mid-prompt.
local function cancel_pending(who, where)
  local function cancel(hits)
    if not hits then return end
    for i = 1, #hits do
      local hit = hits[i]
      if (not who or hit.who == who) and (not where or hit.where == where) then
        hit.cancelled = true
      end
    end
  end
  cancel(runtime.pending)
  cancel(runtime.processing)
end

local function stop_cure(who)
  local last = cures[who]
  if not last then return end
  cures[who] = nil
  killTimer(last.timer)
end

local function blank()
  return {head = 0, torso = 0, rightarm = 0, leftarm = 0, rightleg = 0, leftleg = 0}
end

local function stop_forgetting(who, where)
  local timers = forget[who]
  local entry = timers and timers[where]
  if not entry then return end
  timers[where] = nil
  killTimer(entry.timer)
  if not next(timers) then forget[who] = nil end
end

local function forget_later(who, where)
  local timers = forget[who]
  stop_forgetting(who, where)
  timers = timers or {}
  forget[who] = timers
  local entry = {}
  timers[where] = entry
  entry.timer = tempTimer(svo.lc_forget_after, function()
    if forget[who] ~= timers or timers[where] ~= entry then return end
    timers[where] = nil
    if not next(timers) then forget[who] = nil end
    runtime.expire(who, where)
  end)
end

local function forget_person(who)
  cancel_pending(who)
  for i = 1, #limbs do stop_forgetting(who, limbs[i]) end
  stop_cure(who)
  lastdamage[who], svo.lc_list[who], levels[who] = nil, nil, nil
end

-- The limb's level, named with or without the space ("left leg", "leftleg").
function svo.lc_level(who, where)
  local t = levels[who]
  return t and t[(where:gsub(" ", ""))] or 0
end

-- Damage on one limb, named the same way. A limb broken with no damage behind it reads as
-- broken, so anything asking whether it's broken gets the right answer.
function svo.lc_damage(who, where)
  local t = svo.lc_list[who]
  if not t then return 0 end
  local damage = t[(where:gsub(" ", ""))] or 0
  return svo.lc_level(who, where) == 1 and svo.lc_break_at or damage
end

-- One more hit the size of the last one would break it.
function svo.lc_prepped(who, where)
  local damage = svo.lc_damage(who, where)
  return damage < svo.lc_break_at and damage + (lastdamage[who] or 0) >= svo.lc_break_at
end

local function blank_limb(who, where)
  svo.lc_list[who][where] = 0
  if levels[who] then levels[who][where] = 0 end
  stop_forgetting(who, where)
end

runtime.expire = function(who, where)
  if not svo.lc_list[who] then return end
  blank_limb(who, where)
  raiseEvent("svo limbcounter reset")
end

local function clear_limb(who, where)
  cancel_pending(who, where)
  local last = cures[who]
  local area = limb_area[where]
  if last and (last.area == area or (area == "torso" and last.area == "body")) then
    stop_cure(who)
  end
  stop_forgetting(who, where)
  if svo.lc_list[who] then blank_limb(who, where) end
end

function svo.lc_clearlimb(who, where)
  who, where = player_name(who), limb_name(where)
  if not who or not where then return end
  clear_limb(who, where)
  raiseEvent("svo limbcounter reset")
end

local function get_other_prepped(who, limbhit)
  local s = {}
  for i = 1, #limbs do
    if limbs[i] ~= limbhit and svo.lc_prepped(who, limbs[i]) then
      s[#s + 1] = limbs[i]
    end
  end
  if #s == 0 then
    return ""
  end
  return string.format(" Their %s %s also prepped.", svo.concatand(s), (#s == 1 and 'is' or 'are'))
end

local function record(hit)
  local who, where = hit.who, hit.where
  svo.lc_list[who] = svo.lc_list[who] or blank()
  levels[who] = levels[who] or blank()
  local t = svo.lc_list[who]
  local amount, level = hit.amount, hit.level
  if level then
    level = math.min(math.max(levels[who][where] + 1, level), 3)
    amount = math.max((level - 1) * svo.lc_break_at - t[where], 0)
  else
    lastdamage[who] = amount
  end
  -- the game reports tenths, so don't let float drift decide a break
  t[where] = math.floor((t[where] + amount) * 10 + 0.5) / 10
  local reached = t[where] >= svo.lc_break_at and math.min(math.floor(t[where] / svo.lc_break_at) + 1, 3) or 0
  levels[who][where] = math.max(levels[who][where], reached, level or 0)
  svo.lc_lasthit = who
  forget_later(who, where)
  raiseEvent("svo limbcounter hit", who, where, amount)
  if hit.cancelled then return end

  local others = get_other_prepped(who, where)
  local damage, level = t[where], levels[who][where]
  local stage = level > 0 and string.format(" [L%d]", level) or ""
  if level > 0 or damage >= svo.lc_break_at then
    svo.echof("%s's %s is broken at %g%%%s.%s", who, where, damage, stage, others)
  elseif svo.lc_prepped(who, where) then
    svo.echof("%s's %s is prepped at %g%%%s.%s", who, where, damage, stage, others)
  else
    svo.echof("%s's %s is now at %g%%%s.%s", who, where, damage, stage, others)
  end
end

-- Hits wait for the prompt. An illusion can print a damage line, but it can't spend
-- your balance, and GMCP reports that. Being on both balances means no attack ran, so
-- this works for an attack however it went out, where requiring the [System] queue
-- line would miss anything sent with do, a balance hook or by hand.
function svo.lc_checklimbcounter()
  if #runtime.pending == 0 then return end
  local hits = runtime.pending
  runtime.pending = {}
  if svo.newbals.balance and svo.newbals.equilibrium then return end

  runtime.processing = hits
  moveCursor(0, getLineNumber())
  for i = 1, #hits do
    if not hits[i].cancelled then record(hits[i]) end
  end
  runtime.processing = nil
end

function svo.lc_hit(who, where, howmuch)
  who, where = player_name(who), limb_name(where)
  howmuch = tonumber(howmuch)
  if not who or not where or not howmuch then return end
  local pending = runtime.pending
  pending[#pending + 1] = {who = who, where = where, amount = howmuch}
end

-- DEVASTATE prints no damage line. It breaks both limbs of the pair, at a level set by the
-- fractures behind it, wrists for arms and tendons for legs: 2, 4 or 6 for levels 1, 2 and 3.
-- Its line shows that level. A limb that was already broken goes a level past where it was,
-- so a level 2 strike mangles a limb at level 2.
-- Damage follows from the level: level 2 sits at 100 and level 3 at 200.
function svo.lc_devastate(who, area, level)
  who = player_name(who)
  if not who or not devastated[area] then return end
  local pending = runtime.pending
  for _, where in ipairs(devastated[area]) do
    pending[#pending + 1] = {who = who, where = where, level = level}
  end
end

-- Mending works at once, on the first limb in the area with no damage left to stop it.
local function mend(who, area)
  for _, where in ipairs(bones[area] or {}) do
    if svo.lc_level(who, where) == 1 then
      levels[who][where] = 0
      raiseEvent("svo limbcounter reset")
      return
    end
  end
end

-- Restoration lands on whichever limb in the area needs it by then, left before right, and
-- takes one level off.
local function restore(who, area)
  for _, where in ipairs(salved[area]) do
    local level = svo.lc_level(who, where)
    if level == 2 and not bones[area] then
      blank_limb(who, where)
      raiseEvent("svo limbcounter reset")
      return
    elseif level >= 2 then
      levels[who][where] = level - 1
      svo.lc_list[who][where] = (level - 2) * svo.lc_break_at
      raiseEvent("svo limbcounter reset")
      return
    end
  end
end
runtime.restore = restore

local function needs_restoration(who, area)
  for _, where in ipairs(salved[area]) do
    if svo.lc_level(who, where) >= 2 then return true end
  end
  return false
end

-- A salve line doesn't name the salve, but restoration holds the salve balance until it lands.
-- So any salve before then means the last one wasn't restoration, and an area with nothing for
-- restoration to do can only have been mending.
function svo.lc_salve(who, area)
  who = player_name(who)
  if not who then return end
  local last = cures[who]
  if last then
    stop_cure(who)
    mend(who, last.area)
  end
  if not salved[area] then return end
  if not needs_restoration(who, area) then
    mend(who, area)
    return
  end
  local entry = {area = area}
  cures[who] = entry
  entry.timer = tempTimer(svo.lc_cure_delay, function()
    if cures[who] ~= entry then return end
    cures[who] = nil
    runtime.restore(who, area)
  end)
end

function svo.lc_reset(whom)
  if whom == nil then whom = "" end
  if type(whom) ~= "string" then return end
  local command = whom:lower():match("^%s*(.-)%s*$"):gsub("%s+", " ")
  local person, where
  if command == "all" then
    cancel_pending()
    for who in pairs(forget) do forget_person(who) end
    for who in pairs(cures) do forget_person(who) end
    for who in pairs(svo.lc_list) do forget_person(who) end
    for who in pairs(levels) do forget_person(who) end
    for who in pairs(lastdamage) do forget_person(who) end
    svo.echof("Reset everyone's limb status.")
  else
    where = limb_name(command)
    if command == "" or where then
      person = player_name(target)
      if not person then
        svo.echof("Select a valid current target to reset their limb status.")
        return
      end
    else
      local name, rest = command:match("^(%a+) (.+)$")
      if name then
        person, where = player_name(name), limb_name(rest)
        if not where or name == "all" then person = nil end
      else
        person = player_name(command)
      end
      if not person then
        svo.echof("Use nn [person] [limb], or nn all.")
        return
      end
    end
    if where then
      clear_limb(person, where)
      svo.echof("Reset %s %s's status.", person, where)
    else
      forget_person(person)
      svo.echof("Reset %s's limb status.", person)
    end
  end
  raiseEvent("svo limbcounter reset")
end

local function reading(who, where)
  local damage = svo.lc_list[who][where] or 0
  local level = svo.lc_level(who, where)
  return string.format("%g%%", damage) .. (level > 0 and string.format(" [L%d]", level) or "")
end

function svo.lc_show()
  if not next(svo.lc_list) then
    svo.echof("limbcounter: Not keeping track of anyone yet.")
    return
  end
  setFgColor(unpack(svo.getDefaultColorNums))
  for person in pairs(svo.lc_list) do
    echo("--- " .. person .. " ")
    fg('a_darkgrey')
    echoLink("(reset)", 'svo.lc_reset"' .. person .. '"', "Reset limb status for " .. person, true)
    setFgColor(unpack(svo.getDefaultColorNums))
    echo(string.format(" -- breaks at %g%% ", svo.lc_break_at))
    echo(string.rep("-", 72 - #person))
    echo("\n|")
    for i = 1, #limbs do
      local where = limbs[i]
      local ready = svo.lc_level(person, where) > 0 or svo.lc_prepped(person, where)
      if ready then fg('a_red') end
      echo(string.format("%14s", where .. " " .. reading(person, where)))
      if ready then setFgColor(unpack(svo.getDefaultColorNums)) end
      echo("|")
    end
    echo("\n")
  end
  echo(string.rep("-", 91))
end

-- limbcounters prompt tag is defined here
-- feel free to tinker with it, but move it out into a script of its own,
-- so your changes don't get erased on an update!

local function tag_colour(who, where)
  local ready = svo.lc_level(who, where) > 0 or svo.lc_prepped(who, where)
  return ready and "<a_red>" or "<a_darkyellow>"
end

-- Show only the selected opponent, and keep UI readings separate from the combat accessor.
local function readings()
  local who = player_name(target)
  return who, who and svo.lc_list[who]
end

function svo.lc_prompttag2()
  local who, t = readings()
  if not t then return "" end
  return string.format("%s: h %s|t %s|ra %s|la %s|rl %s|ll %s", who,
    reading(who, 'head'), reading(who, 'torso'), reading(who, 'rightarm'), reading(who, 'leftarm'),
    reading(who, 'rightleg'), reading(who, 'leftleg'))
end

svo.adddefinition("@lc_prompttag2", "svo.lc_prompttag2()")

function svo.lc_prompttag()
  local who, t = readings()
  if not t then return "" end
  return string.format("%s%s<a_white>/%s%s<a_white>|%s%s<a_white>/%s%s<a_white>|%s%s<a_white>/%s%s<a_white>|%g",
    tag_colour(who, 'leftarm'), reading(who, 'leftarm'), tag_colour(who, 'rightarm'), reading(who, 'rightarm'),
    tag_colour(who, 'leftleg'), reading(who, 'leftleg'), tag_colour(who, 'rightleg'), reading(who, 'rightleg'),
    tag_colour(who, 'head'), reading(who, 'head'), tag_colour(who, 'torso'), reading(who, 'torso'), svo.lc_break_at)
end

svo.adddefinition("@lc_prompttag", "svo.lc_prompttag()")

function svo.lc_prompttag3()
  local who, t = readings()
  if not t then return "" end
  return string.format(
    "<a_darkgrey>(%s%s<a_darkgrey>:%s%s<a_darkgrey>:%s%s<a_darkgrey>:%s%s<a_darkgrey>:%s%s<a_darkgrey>:%s%s<a_darkgrey>:%g)",
    tag_colour(who, 'leftarm'), reading(who, 'leftarm'), tag_colour(who, 'rightarm'), reading(who, 'rightarm'),
    tag_colour(who, 'leftleg'), reading(who, 'leftleg'), tag_colour(who, 'rightleg'), reading(who, 'rightleg'),
    tag_colour(who, 'head'), reading(who, 'head'), tag_colour(who, 'torso'), reading(who, 'torso'), svo.lc_break_at)
end

svo.adddefinition("@lc_prompttag3", "svo.lc_prompttag3()")

-- Reuse one named signal owner, resolving the current implementation after each reload.
runtime.check = runtime.check or function() svo.lc_checklimbcounter() end
svo.signals.before_prompt_processing:connect(runtime.check, "svo.lc_checklimbcounter")
end
if svo.systemloaded then svo.loader.limbcounter() end
