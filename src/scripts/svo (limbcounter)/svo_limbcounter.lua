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
local short = {h = 'head', t = 'torso', rl = 'rightleg', ll = 'leftleg', ra = 'rightarm', la = 'leftarm'}
-- what a salve line can name, in the order a cure takes the limbs
local salved = {
  head = {'head'}, torso = {'torso'}, body = {'torso'},
  arms = {'leftarm', 'rightarm'}, legs = {'leftleg', 'rightleg'},
}

-- what mending can reach
local bones = {arms = salved.arms, legs = salved.legs}

-- what DEVASTATE strikes
local devastated = {arms = {'leftarm', 'rightarm'}, legs = {'leftleg', 'rightleg'}}

local pending, forget, cures, lastdamage = {}, {}, {}, {}

svo.lc_percent = true
svo.lc_list = svo.lc_list or {}
svo.lc_levels = svo.lc_levels or {}
svo.lc_lasthit = svo.lc_lasthit or ""
svo.lc_break_at = 100
svo.lc_forget_after = 180
-- Restoration lands at 4 seconds, as its salve balance comes back, so the person's next salve
-- can reach us at the same moment. This stays ahead of that line.
svo.lc_cure_delay = 3.7

local levels = svo.lc_levels

local function blank()
  return {head = 0, torso = 0, rightarm = 0, leftarm = 0, rightleg = 0, leftleg = 0}
end

local function stop_forgetting(who, where)
  if forget[who] and forget[who][where] then
    killTimer(forget[who][where])
    forget[who][where] = nil
  end
end

local function forget_later(who, where)
  stop_forgetting(who, where)
  forget[who] = forget[who] or {}
  forget[who][where] = tempTimer(svo.lc_forget_after, function()
    forget[who][where] = nil
    svo.lc_clearlimb(who, where)
  end)
end

local function forget_person(who)
  for i = 1, #limbs do stop_forgetting(who, limbs[i]) end
  if cures[who] then killTimer(cures[who].timer) end
  cures[who], lastdamage[who], svo.lc_list[who], levels[who] = nil, nil, nil, nil
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

function svo.lc_clearlimb(who, where)
  if not svo.lc_list[who] then return end
  blank_limb(who, where)
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

  local others = get_other_prepped(who, where)
  local damage = svo.lc_damage(who, where)
  if damage >= svo.lc_break_at then
    svo.echof("%s's %s is broken at %g%%.%s", who, where, damage, others)
  elseif svo.lc_prepped(who, where) then
    svo.echof("%s's %s is prepped at %g%%.%s", who, where, damage, others)
  else
    svo.echof("%s's %s is now at %g%%.%s", who, where, damage, others)
  end
end

-- Hits wait for the prompt. An illusion can print a damage line, but it can't spend
-- your balance, and GMCP reports that. Being on both balances means no attack ran, so
-- this works for an attack however it went out, where requiring the [System] queue
-- line would miss anything sent with do, a balance hook or by hand.
function svo.lc_checklimbcounter()
  if #pending == 0 then return end
  local hits = pending
  pending = {}
  if svo.newbals.balance and svo.newbals.equilibrium then return end

  moveCursor(0, getLineNumber())
  for i = 1, #hits do record(hits[i]) end
end

function svo.lc_hit(who, where, howmuch)
  where = where:gsub(" ", "")
  if not blank()[where] or not tonumber(howmuch) then return end
  pending[#pending + 1] = {who = who:lower():title(), where = where, amount = tonumber(howmuch)}
end

-- DEVASTATE prints no damage line. It breaks both limbs of the pair, at a level set by the
-- fractures behind it, wrists for arms and tendons for legs: 2, 4 or 6 for levels 1, 2 and 3.
-- Its line shows that level. A limb that was already broken goes a level past where it was,
-- so a level 2 strike mangles a limb at level 2.
-- Damage follows from the level: level 2 sits at 100 and level 3 at 200.
function svo.lc_devastate(who, area, level)
  if not devastated[area] then return end
  for _, where in ipairs(devastated[area]) do
    pending[#pending + 1] = {who = who:lower():title(), where = where, level = level}
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
      svo.lc_clearlimb(who, where)
      return
    elseif level >= 2 then
      levels[who][where] = level - 1
      svo.lc_list[who][where] = (level - 2) * svo.lc_break_at
      raiseEvent("svo limbcounter reset")
      return
    end
  end
end

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
  local last = cures[who]
  if last then
    killTimer(last.timer)
    cures[who] = nil
    mend(who, last.area)
  end
  if not salved[area] then return end
  if not needs_restoration(who, area) then
    mend(who, area)
    return
  end
  cures[who] = {area = area, timer = tempTimer(svo.lc_cure_delay, function()
    cures[who] = nil
    restore(who, area)
  end)}
end

function svo.lc_reset(whom)
  if whom == "" then whom = nil end
  local lasthit = svo.lc_list[svo.lc_lasthit] and svo.lc_lasthit
  local limb = whom and short[whom:lower()]
  whom = whom and string.title(whom)

  if whom == 'All' then
    for person in pairs(svo.lc_list) do forget_person(person) end
    svo.echof("Reset everyone's limb status.")
  elseif limb then
    if not lasthit then
      svo.echof("Not keeping track of anyone yet to reset their limb.")
      return
    end
    blank_limb(lasthit, limb)
    svo.echof("Reset %s %s's status.", lasthit, limb)
  elseif whom then
    if not svo.lc_list[whom] then
      svo.echof("Weren't keeping track of %s anyway.", whom)
      return
    end
    forget_person(whom)
    svo.echof("Reset %s's limb status.", whom)
  elseif lasthit then
    forget_person(lasthit)
    svo.echof("Reset %s's limb status.", lasthit)
  else
    svo.echof("Not keeping track of anyone to reset them anyway.")
    return
  end
  raiseEvent("svo limbcounter reset")
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
      local damage = svo.lc_damage(person, where)
      local ready = damage >= svo.lc_break_at or svo.lc_prepped(person, where)
      if ready then fg('green') end
      echo(string.format("%14s", string.format("%s %g%%", where, damage)))
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
  local ready = svo.lc_damage(who, where) >= svo.lc_break_at or svo.lc_prepped(who, where)
  return ready and "<a_red>" or "<a_darkyellow>"
end

-- Every limb of the last person hit, as lc_damage reads it.
local function readings()
  local who = svo.lc_lasthit
  if not svo.lc_list[who] then return who end
  local t = {}
  for i = 1, #limbs do t[limbs[i]] = svo.lc_damage(who, limbs[i]) end
  return who, t
end

function svo.lc_prompttag2()
  local who, t = readings()
  if not t then return "" end
  return string.format("%s: h %g|t %g|ra %g|la %g|rl %g|ll %g", who, t.head, t.torso, t.rightarm, t.leftarm,
    t.rightleg, t.leftleg)
end

svo.adddefinition("@lc_prompttag2", "svo.lc_prompttag2()")

function svo.lc_prompttag()
  local who, t = readings()
  if not t then return "" end
  return string.format("%s%g<a_white>/%s%g<a_white>|%s%g<a_white>/%s%g<a_white>|%s%g<a_white>/%s%g<a_white>|%g",
    tag_colour(who, 'leftarm'), t.leftarm, tag_colour(who, 'rightarm'), t.rightarm,
    tag_colour(who, 'leftleg'), t.leftleg, tag_colour(who, 'rightleg'), t.rightleg,
    tag_colour(who, 'head'), t.head, tag_colour(who, 'torso'), t.torso, svo.lc_break_at)
end

svo.adddefinition("@lc_prompttag", "svo.lc_prompttag()")

function svo.lc_prompttag3()
  local who, t = readings()
  if not t then return "" end
  return string.format(
    "<a_darkgrey>(%s%g<a_darkgrey>:%s%g<a_darkgrey>:%s%g<a_darkgrey>:%s%g<a_darkgrey>:%s%g<a_darkgrey>:%s%g<a_darkgrey>:%g)",
    tag_colour(who, 'leftarm'), t.leftarm, tag_colour(who, 'rightarm'), t.rightarm,
    tag_colour(who, 'leftleg'), t.leftleg, tag_colour(who, 'rightleg'), t.rightleg,
    tag_colour(who, 'head'), t.head, tag_colour(who, 'torso'), t.torso, svo.lc_break_at)
end

svo.adddefinition("@lc_prompttag3", "svo.lc_prompttag3()")

-- looked up by name, because the loaders run again on a class change, and a check left
-- over from an earlier load would hold a pending list nothing adds to
svo.signals.before_prompt_processing:connect(function() svo.lc_checklimbcounter() end, "svo.lc_checklimbcounter")
end
if svo.systemloaded then svo.loader.limbcounter() end
