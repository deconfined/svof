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

It also has a feature of showing the last hit opponents limb status on the prompt - to use this, add the *@lc_prompttag*, *@lc_prompttag2* or *@lc_prompttag3* tag to your :ref:`custom prompt<customprompt>`. The tags display the limbs in red when they're broken or prepped.

If you just want to keep your prompt as-is, then you can use this: ::

	vconfig customprompt ^1@healthh, ^2@manam, ^5@endurancee, ^4@willpowerw ^W@eqbal@defs^b|@lc_prompttag^W- @affs

You might also find this `example targetting alias <http://www.ironrealms.com/mud-scripts/example-hit-a-targetted-limb-alias>`_ useful for attacking with.

Aliases
^^^^^^^^^^
.. glossary::

  vsl
  	Shows limb data of everything that the counter is keeping track of.

  nn
  	Resets the limb data of the last hit person.

  nn *person*
  	Resets the limb data of a given *person*.

  nn *t/h/rl/ll/ra/la*
  	Resets a specific limb of the last hit person.

  nn *all*
  	Resets the limb data of everyone.

API
^^^^^^^^^^
.. glossary::

  svo limbcounter hit (who, where, amount) (event)
  	This `Mudlet event <http://doc.svo.vadisystems.com/#event-use-examples>`_ goes off when you've hit someone's limb. The event arguments include whom and where did you hit them, and the percentage the hit dealt.

  svo limbcounter reset
  	This event is raised when a limb clears, a cure lands or a limb or person is reset. You can then re-read the current *svo.lc_list* table to get the current values.

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
  	Stores the last hit persons name, or an empty string if you haven't hit anyone yet. You can use it to check a specific limb status in an alias, for example: ::

  		echo(string.format("%s's head is at %s%%.\n", svo.lc_lasthit, svo.lc_damage(svo.lc_lasthit, "head")))
