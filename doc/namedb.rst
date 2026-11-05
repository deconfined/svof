Svof NameDB
===========

NameDB is svof's native SQLite character database and name highlighter. There is
one database and one policy/highlighting implementation, not a second endeeb
installation. Character facts come exclusively from the official Achaea HTTPS
API. Discovering a name is not proof that any character fact is known.

Authority cutover and backup
----------------------------

**Before the first upgrade, close Mudlet and make an offline backup of
``Database_namedb.db`` in the profile directory.** Also back up personal settings
under ``svo/config`` (including watchfor/highlightignore) and
``svo/namedb/citypolitics``. Do not copy a live SQLite database as your backup.
Restart the profile after replacing the old package so no old package-created
anonymous handlers remain in memory. Do not paste only the HTTP script over an
older NameDB tree: install the matching scripts, aliases and trigger metadata.

The first load performs authority migration version 1. It clears old character
facts, including manual facts and identity fields that the API cannot supply.
Names, personal notes, IFF, importance, city/house/order enemy flags, highlighting
preferences, watchfor, highlightignore and city politics are preserved. The
migration adds columns without rebuilding the people table or removing custom
columns, indexes, triggers or unrelated tables. The fact reset and authority
version are committed together; a failed reset rolls both back and surfaces the
error. Mudlet may continue loading sibling scripts after that error, so native
readers/highlights expose identity as unknown and acquisition refuses to start
until authority migration succeeds; rolled-back manual facts are not a fallback.
Personal policies and the underlying SQLite rows remain intact. The committed
reset raises ``NameDB facts reset`` once, when native readers are ready. Subsequent reloads and fresh connections preserve verified API
cache; they do not repeatedly wipe it.

A valid character response replaces every API-owned fact, even if somebody
edited the factual SQLite columns manually. Hidden or missing values become
unknown; old values are not used as a hidden-city fallback. Transport errors,
unreadable/oversized files, invalid JSON or supplied field types/values, and
mismatched names leave verified facts intact. API responses never replace personal policies, annotations or
custom columns. Direct SQL edits bypass the NameDB API and are not supported as
an alternate identity source.

What can be known
-----------------

The API supplies name, fullname (stored as ``title``), class, city, house (stored
as ``guild``), level, XP rank, mob kills, player kills and explorer rank.
``api_verified`` and ``api_updated`` describe the last accepted API response;
they are not an assertion that unsupported fields are known or that the
character has not changed since that request. Class is lowercase; city is title
case, ``rogue`` for explicit no citizenship, or ``Undead`` for API underworld.
An unknown/hidden city is the empty string, and is **not** treated as rogue by
the highlighter. XP rank 0 from the API is represented by native unranked ``-2``;
unknown numeric facts use ``-1``. Abbreviated mob kills remain text.

This integration has no authoritative API source for gender, race, order, city
rank/soldier, dragon, immortal, mark, infamy, might, combat rank/rating,
birthday, arms, divorces, motto or warcry; those remain unknown. Level alone is
not a dragon/immortal assertion.
The old ``qwm``, ``qwi``, ``qwic`` and ``ndb infamous`` views, factual editor
choices, combat-class writer and honours acquisition/parser are removed, not
silently refreshed from the game. Order/divine highlight preferences are kept
as preferences, but cannot identify members without authoritative facts.

Working with it
---------------

HTTPS lookup of discovered, unverified names is automatic. The old ``autocheck``
option and menu toggle are removed; a saved disabled value cannot suppress
non-blocking API requests. Names discovered in existing game lists, common
discovery messages and imports can be retained, but their list colours,
classes and other identity claims do not write facts. Existing city/clan/friend/party class annotations and
summaries remain, explicitly labelled as cached API classes. Unsupported Dragon
annotations/counters are removed rather than reporting a false zero. City/house/order enemy-list enrichment remains a
personal policy operation. Each discovered unknown name is attempted at most
once per session; failures/cancellations are not automatically retried. Use an
explicit lookup/refresh to try again. Reload retains this attempted-name set.

Every lookup uses ``downloadFile`` with an exactly owned unique temporary path,
including the online list (which can exceed getHTTP's event-body limit). Only
validated ASCII character names (3–30 letters) are used to build official HTTPS
URLs; response URIs are never followed. Three requests may run concurrently,
with a 30-second timeout and 1 MiB response limit. Pending requests deduplicate
by canonical name. Cancellation, deletion, disconnect, exit and reload settle
pending work; late owned responses are discarded and their files removed.
Unrelated download events and files are untouched. No retries, HONOURS,
HONORSB, server queue, equilibrium waits or generated game commands participate
in acquisition.

Aliases
-------

``ndb lookup <name>``
  Look up one character, including an offline/hidden-online-list character.
``ndb online`` / ``qw`` / ``qw2``
  Fetch the official online name list and automatically look up unverified
  people not already attempted this session. This does not send the game's QW/QWC commands.
``qw update``
  Fetch the online list and explicitly request every listed character's facts.
``qwc``
  Display online names grouped by their **cached API city**. Newly discovered or
  hidden cities are shown as unknown while lookups are pending.
``ppof <city>``
  Explicitly request an online list and report matching cached-city members to
  your configured cc destination. This is user-requested reporting, not an
  automatic lookup side effect; the report is labelled as cached API city.
``ndb refresh``
  Explicitly request unknown/unverified names already in the database.
``ndb update all`` / ``ndb update unranked``
  Explicitly refresh all known people, or only known unranked people. Updating
  100 or more matching people requires repeating the corresponding command to confirm. Neither
  command clears good cached facts while requests are in flight.
``ndb cancel``
  Cancel pending and queued HTTPS requests. Verified facts remain intact.
``whois <name>``
  Show cached API facts and their timestamp, unsupported fields as unknown, and
  personal policies/notes. An unknown name starts an HTTPS lookup; run whois
  again after it completes.
``ndb set <name> notes/iff/importance/cityenemy/houseenemy/orderenemy <value>``
  Edit personal policy/annotations only. Notes accept literal ``\n`` line breaks.
  IFF values are -1 automatic, 1 enemy and 2 ally.
``iff <name> ally/enemy/auto``
  Personal ally overrides city politics and all enemy flags; personal enemy
  always marks an enemy; auto uses politics and city/house/order enemy flags.
``city/house/order enemies [add]``
  Explicitly request the corresponding game's policy list. ``add`` also
  discovers unknown names and applies their enemy flag. This remains separate
  from HTTPS fact acquisition.
``vconfig politics`` / ``npp [on/off]``
  Configure city politics/highlight preferences or toggle name highlighting.
``vconfig highlightignore <name>`` / ``vshow highlightignore``
  Keep personal exceptions to name highlighting. Watchfor preferences are also
  preserved and still take precedence in native highlighting.
``ndb export`` / ``ndb import``
  Export native records, or import names and selected personal policy fields.
  Old exported identity facts are not a way around API authority. Imports do
  not delete existing names. Export only the annotations you intend to share.
``ndb delete <name>`` / ``ndb delete all`` / ``ndb delete unranked``
  Delete records (the bulk commands require confirmation). Outstanding requests
  are cancelled first so late responses cannot restore deleted rows.
``ndb stats`` / ``ndb`` / ``ndb long``
  Show cached city/name counts or the short/expanded alias cheatsheet.

Scripting API
-------------

``ndb.lookup(name)`` validates/canonicalizes a name and schedules one request.
It returns true when scheduled/already pending, or nil plus an input error.
``ndb.lookup_online(refresh)`` discovers online names; true refresh explicitly
requests their facts as well. ``ndb.refresh(scope)`` accepts ``new`` (default),
``all`` or ``unranked``. ``ndb.cancel_lookups([name])`` cancels one character or
all requests (including the online list). These are asynchronous APIs, not
synchronous getters. On each accepted character update, **after SQLite commit**,
NameDB emits ``NameDB character updated`` with the canonical character name.
Consumers may safely read the committed row inside that event. An event is not
permission to submit an attack.

Native read/policy interfaces remain available: ``exists``, ``isperson``,
``getname``, ``getclass``, ``isclass``, ``getcity``, city membership helpers,
``getxprank``, ``getnotes``, ``isenemy``, ``iscityenemy``, ``isonlycityenemy``,
``setiff``, ``getcolor``, ``getcolorn``, ``getcolorp``, formatting/highlight
helpers and name extraction helpers. ``getname`` returns the native SQLite
row, including custom fields. Unknown names return nil from row/fact getters;
known names with unknown class/city return the native empty string. Unsupported
identity readers return their documented unknown value, not fresh negative
facts. Writable identity APIs (including setclass/setdragon/setmark/setinfamous)
are removed. ``ndb.addname(name_or_list)`` discovers names and triggers automatic
lookup processing without an enable/disable setting. Use ``ndb.lookup`` to force
a refresh, not direct SQL plus an old honours event.

Tests
-----

From the standalone svof checkout, run ``lua tools/test_namedb.lua``. It loads
native ScriptGroup bodies and leaf scripts in metadata order, uses the same
pinned actual Mudlet 4.19.1 DB.lua provider as the Hunting suite (vendored
byte-for-byte under tools/testfixtures, GPL-2.0 with COPYING/provenance), real
LuaSQL SQLite 2.6.0-2 and real lua-yajl 2.1-0. Only client I/O, time and static
event dispatch are controlled. Install the matching Lua ABI's rocks with
``luarocks install luasql-sqlite3 2.6.0-2`` and
``luarocks install lua-yajl 2.1-0``; YAJL/SQLite development headers are needed.
The fixture creates temporary profiles only and never reads an installed one.
