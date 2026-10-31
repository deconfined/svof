-- Svof (c) 2011-2018 by Vadim Peretokin
-- Svof is licensed under a
-- Creative Commons Attribution-NonCommercial-ShareAlike 4.0 International License.
-- You should have received a copy of the license along with this
-- work. If not, see <http://creativecommons.org/licenses/by-nc-sa/4.0/>.

-- Tracks the limb damage you deal, from the percentage the game prints with each hit.
-- A limb breaks at 100 and damage keeps adding up past that, with level 2 at 200 and
-- level 3 at 300. A limb clears when the person cures it, or after svo.lc_forget_after
-- seconds without a hit.

svo.loader.limbcounter = function()
local limbs = {'head', 'torso', 'rightarm', 'leftarm', 'rightleg', 'leftleg'}
local short = {h = 'head', t = 'torso', rl = 'rightleg', ll = 'leftleg', ra = 'rightarm', la = 'leftarm'}
-- what a salve line can name, in the order a cure takes the limbs
local salved = {
  head = {'head'}, torso = {'torso'}, body = {'torso'},
  arms = {'leftarm', 'rightarm'}, legs = {'leftleg', 'rightleg'},
}

-- what DEVASTATE strikes
local devastated = {arms = {'leftarm', 'rightarm'}, legs = {'leftleg', 'rightleg'}}

local pending, forget, cures, lastdamage = {}, {}, {}, {}

svo.lc_percent = true
svo.lc_list = svo.lc_list or {}
svo.lc_lasthit = svo.lc_lasthit or ""
svo.lc_break_at = 100
svo.lc_forget_after = 180
svo.lc_cure_delay = 4

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
  if cures[who] then killTimer(cures[who]) end
  cures[who], lastdamage[who], svo.lc_list[who] = nil, nil, nil
end

-- Damage on one limb, named with or without the space ("left leg", "leftleg").
function svo.lc_damage(who, where)
  local t = svo.lc_list[who]
  return t and t[(where:gsub(" ", ""))] or 0
end

-- One more hit the size of the last one would break it.
function svo.lc_prepped(who, where)
  local damage = svo.lc_damage(who, where)
  return damage < svo.lc_break_at and damage + (lastdamage[who] or 0) >= svo.lc_break_at
end

function svo.lc_clearlimb(who, where)
  if not svo.lc_list[who] then return end
  svo.lc_list[who][where] = 0
  stop_forgetting(who, where)
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
  local t = svo.lc_list[who]
  local amount = hit.amount
  if amount then
    lastdamage[who] = amount
  else
    amount = math.max(hit.level * svo.lc_break_at - t[where], 0)
  end
  -- the game reports tenths, so don't let float drift decide a break
  t[where] = math.floor((t[where] + amount) * 10 + 0.5) / 10
  svo.lc_lasthit = who
  forget_later(who, where)
  raiseEvent("svo limbcounter hit", who, where, amount)

  local others = get_other_prepped(who, where)
  if t[where] >= svo.lc_break_at then
    svo.echof("%s's %s is broken at %g%%.%s", who, where, t[where], others)
  elseif svo.lc_prepped(who, where) then
    svo.echof("%s's %s is prepped at %g%%.%s", who, where, t[where], others)
  else
    svo.echof("%s's %s is now at %g%%.%s", who, where, t[where], others)
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

-- DEVASTATE prints no damage line. It breaks both limbs of the pair, at a level set by
-- the fractures behind it (2, 4 or 6 for levels 1, 2 and 3), and its line shows the level.
function svo.lc_devastate(who, area, level)
  if not devastated[area] then return end
  for _, where in ipairs(devastated[area]) do
    pending[#pending + 1] = {who = who:lower():title(), where = where, level = level}
  end
end

-- A cure takes a few seconds to land, and takes the first broken limb in the area.
function svo.lc_salve(who, area)
  if not salved[area] then return end
  if cures[who] then killTimer(cures[who]) end
  cures[who] = tempTimer(svo.lc_cure_delay, function()
    cures[who] = nil
    for _, where in ipairs(salved[area]) do
      if svo.lc_damage(who, where) >= svo.lc_break_at then
        svo.lc_clearlimb(who, where)
        return
      end
    end
  end)
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
    svo.lc_list[lasthit][limb] = 0
    stop_forgetting(lasthit, limb)
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
  for person, limbt in pairs(svo.lc_list) do
    echo("--- " .. person .. " ")
    fg('a_darkgrey')
    echoLink("(reset)", 'svo.lc_reset"' .. person .. '"', "Reset limb status for " .. person, true)
    setFgColor(unpack(svo.getDefaultColorNums))
    echo(string.format(" -- breaks at %g%% ", svo.lc_break_at))
    echo(string.rep("-", 72 - #person))
    echo("\n|")
    for i = 1, #limbs do
      local where = limbs[i]
      local ready = limbt[where] >= svo.lc_break_at or svo.lc_prepped(person, where)
      if ready then fg('green') end
      echo(string.format("%14s", string.format("%s %g%%", where, limbt[where])))
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

function svo.lc_prompttag2()
  local who, t = svo.lc_lasthit, svo.lc_list[svo.lc_lasthit]
  if not t then return "" end
  return string.format("%s: h %g|t %g|ra %g|la %g|rl %g|ll %g", who, t.head, t.torso, t.rightarm, t.leftarm,
    t.rightleg, t.leftleg)
end

svo.adddefinition("@lc_prompttag2", "svo.lc_prompttag2()")

function svo.lc_prompttag()
  local who, t = svo.lc_lasthit, svo.lc_list[svo.lc_lasthit]
  if not t then return "" end
  return string.format("%s%g<a_white>/%s%g<a_white>|%s%g<a_white>/%s%g<a_white>|%s%g<a_white>/%s%g<a_white>|%g",
    tag_colour(who, 'leftarm'), t.leftarm, tag_colour(who, 'rightarm'), t.rightarm,
    tag_colour(who, 'leftleg'), t.leftleg, tag_colour(who, 'rightleg'), t.rightleg,
    tag_colour(who, 'head'), t.head, tag_colour(who, 'torso'), t.torso, svo.lc_break_at)
end

svo.adddefinition("@lc_prompttag", "svo.lc_prompttag()")

function svo.lc_prompttag3()
  local who, t = svo.lc_lasthit, svo.lc_list[svo.lc_lasthit]
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
