Svof Limbcounter
======================================
The limbcounter tracks the limb damage you deal to whoever you hit, from the percentage the game reports with each hit. It works for any class the game reports that for, and tells you the limb's status after each hit, along with any limbs that are prepped.

A limb breaks at 100%, and damage keeps adding up past that. A limb counts as prepped when one more hit the size of your last one would break it.

A broken limb's level says how many salves it takes to heal:

* Level 1 is broken, with no damage behind it. Mending cures it.
* Level 2 is damaged, from 100%. Restoration takes the damage away, which leaves level 1.
* Level 3 is mangled, from 200%. Restoration leaves level 2, at 100%.

Head and torso have no bones to mend, so restoration heals them outright from level 2. Any limb also clears after 3 minutes without a hit.

DEVASTATE doesn't report a percentage. Its line shows the break level, set by wrist fractures for the arms and torn tendons for the legs, and both limbs of the pair go to that level. A limb that was already broken goes a level past where it was, up to level 3.

A hit counts however you sent it: the system, the ``do`` queue, the game's own queue or by hand. Since an illusion can print a damage line, a line only counts if you are off balance or equilibrium at the prompt after it.

A salve line doesn't say which salve was used, but restoration holds the salve balance until it lands. So a salve counts as restoration if 3.7 seconds pass with no other salve from that person, and it takes one level off the first limb in the area that needs it, left before right. A salve sooner than that means the last one wasn't restoration. Where no limb in the area needs restoration, the salve can only be mending, which acts at once. A lone epidermal on the body still looks like restoration, so it can take a level off the torso.

The *@lc_prompttag*, *@lc_prompttag2* and *@lc_prompttag3* :ref:`custom prompt<customprompt>` tags follow the current global ``target``, not the last person hit. They show raw percentages, with a suffix for a nonzero game break stage: ``0% [L1]`` means a mending-only break, ``100% [L2]`` means damaged, and ``200% [L3]`` means mangled. Broken or prepped limbs are red. An invalid, missing or untracked target produces an empty tag; it never falls back to another opponent. Selecting a target does not invent a new zero-damage record.

If you just want to keep your prompt as-is, then you can use this: ::

	vconfig customprompt ^1@healthh, ^2@manam, ^5@endurancee, ^4@willpowerw ^W@eqbal@defs^b|@lc_prompttag^W- @affs

You might also find this `example targetting alias <http://www.ironrealms.com/mud-scripts/example-hit-a-targetted-limb-alias>`_ useful for attacking with.

Reloads and upgrades
^^^^^^^^^^^^^^^^^^^
Damage, break stages, queued hits and timer ownership survive loader reruns and class changes. A valid pending restoration retains its original deadline, and refreshing a hit cancels the old expiry even if it was created before reload.

Restart Mudlet when first upgrading from the older closure-local tracker. Its already-scheduled timers are inaccessible to the new code; installing the fixed source in the same running session cannot safely recover them. Subsequent reloads under the fixed tracker do not need that restart.

Manual resets discard matching queued hits and expiry work. Resetting a person cancels their inferred cure; resetting one limb cancels a pending cure inference for its area, without cancelling unrelated areas or other people. A later hit starts fresh tracking.

Limb 1.8 comparison
^^^^^^^^^^^^^^^^^^^
The supplied ``Limb1.8.mpackage`` was checked against this tracker. Its two
percentage messages, salve observation, three-minute expiry, resets and
current-target display are already covered. Its change for damage at or above
200% subtracts 100 on the first restoration; the native tracker already keeps
the more complete break-stage model and the final mending-only break.

A direct source comparison starting at 230% produced 230 -> 130 -> 0 in
Limb 1.8. Native raw percentages were 230 -> 100 -> 0 -> 0, with stages
3 -> 2 -> 1 -> 0. At stage 1, ``lc_damage`` deliberately returns 100 to
combat callers while the raw display remains ``0% [L1]``.

No missing tracking capability was established from 1.8. Its residual-percentage
arithmetic is not adopted: the source comparison above is not a live-game
measurement, and the available game captures do not distinguish preserving
overshoot from resetting to the lower stage's threshold. A controlled mangled
limb/restoration capture is still needed for that boundary.

Do not restore the ``Running queued`` gate, ``lb`` timers, wsys prompt tag or
class-based display suppression: those would lose native/manual hit coverage,
stage information or reload/reset ownership. The original package remains
comparison input, not a runtime dependency.


Aliases
^^^^^^^^^^
.. glossary::

  vsl
  	Shows every tracked opponent, using raw percentages and nonzero break-stage suffixes. It remains an all-opponent view even though prompt tags follow the current target.

  nn
  	Resets the current target's limb data. No valid current target means no reset; the last person hit is never substituted.

  nn *person*
  	Resets the limb data of a given *person*.

  nn *limb*
  	Resets a limb of the current target. Accepts ``h/head``, ``t/torso``, ``la/leftarm/left arm``, ``ra/rightarm/right arm``, ``ll/leftleg/left leg`` and ``rl/rightleg/right leg``.

  nn *person* *limb*
  	Resets that limb of a named opponent, regardless of the current target. For example, ``nn Bob left leg`` or ``nn Bob ll``. Names and limb spellings are case-insensitive and tolerate surrounding whitespace.

  nn *all*
  	Resets everyone, including queued hits not yet accepted at a prompt. Invalid multiword commands do not reset anything.

API
^^^^^^^^^^
.. glossary::

  svo limbcounter hit (who, where, amount) (event)
  	This `Mudlet event <http://doc.svo.vadisystems.com/#event-use-examples>`_ goes off when you've hit someone's limb. The event arguments include whom and where did you hit them, and the percentage the hit dealt.

  svo limbcounter reset
  	This event is raised when a limb clears, a cure lands or a limb or person is reset. You can then re-read the current *svo.lc_list* table to get the current values.

  svo.lc_reset (command)
  	Uses the same command forms as ``nn``. A nil or empty command selects the current target, not ``svo.lc_lasthit``.

  svo.lc_clearlimb (who, where)
  	Resets a named opponent's limb, cancelling its matching queued hits, expiry and inferred cure for that area. Player names and limb spellings are normalized as for ``nn``.

  svo.lc_damage (who, where)
  	Returns the damage on one limb, named with or without the space, such as "left leg" or "leftleg". It's 0 for anyone not being tracked, and 100 for a limb at level 1, so a broken limb always reads as broken.

  svo.lc_level (who, where)
  	Returns the limb's break level, from 0 to 3, named the same way.

  svo.lc_prepped (who, where)
  	Returns true if one more hit the size of your last one would break the limb.

  svo.lc_list (table)
  	A table containing all of the limbcounters tracking data - organized by named tables of people and their limb damage, as dealt. ::

	  	display(svo.lc_list)

	  	--[[yields, for example:
		table {
		  'Person2': table {
		    'head': 0
		    'torso': 12.3
		    'rightarm': 25.2
		    'leftarm': 16.8
		    'rightleg': 58.8
		    'leftleg': 100.8
		  }
		}
		]]

  svo.lc_lasthit (string)
  	Stores the last hit person's name, or an empty string if no hit has been recorded. This is informational; it does not select an implicit reset or prompt display. Read raw percentages from ``lc_list`` and break stages from ``lc_level`` when writing your own display: ::

  		local who = svo.lc_lasthit
  		local hits = svo.lc_list[who]
  		if hits then
  		  echo(string.format("%s's head: %g%% [L%d].\n", who, hits.head, svo.lc_level(who, "head")))
  		end
