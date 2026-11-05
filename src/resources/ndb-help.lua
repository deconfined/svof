--v02: official API authority; personal policies remain local
{
  { term = "ndb / ndb long", definition = { "Show the native NameDB alias cheatsheet, short or expanded." } },
  { term = "ndb lookup <name>", definition = { "Look up one character through the official HTTPS API. No game command or equilibrium is used." } },
  { term = "ndb online / qw / qw2", definition = { "Fetch the official online name list and automatically look up newly discovered unverified names over HTTPS. No lookup toggle is required." } },
  { term = "qw update", definition = { "Explicitly refresh every character on the official online list; good cache remains visible until a valid response replaces it." } },
  { term = "qwc", definition = { "Group online names by their cached authoritative city. Hidden/missing city is unknown, not rogue." } },
  { term = "ppof <city>", definition = { "Explicitly report online matching cached-city names to the configured cc destination, labelled as cached API city." } },
  { term = "ndb refresh", definition = { "Explicitly look up unknown/unverified names already in SQLite. This replaces the old honours backlog operation." } },
  { term = "ndb update all / ndb update unranked", definition = { "Refresh all known names, or only known unranked names. Updating 100 or more names requires confirmation." } },
  { term = "ndb cancel", definition = { "Cancel all pending/queued HTTP requests without clearing verified facts. Late owned responses are discarded." } },
  { term = "whois <name>", definition = { "Show cached API facts, timestamp, unknown unsupported facts, and personal notes/policies. Unknown names start an HTTPS lookup." } },
  { term = "vconfig politics", definition = { "Configure personal city politics and highlight preferences. API updates never replace these preferences." } },
  { term = "npp [on/off]", definition = { "Toggle native name highlighting. Unknown cities are not highlighted as rogues." } },
  { term = "vconfig highlightignore <name> / vshow highlightignore", definition = { "Manage/view personal highlighting exceptions. Watchfor and highlighting preferences are preserved." } },
  { term = "iff <name> ally/enemy/auto", definition = { "Set personal IFF: ally overrides all enemy policies, enemy is always enemy, auto uses politics and list-enemy flags." } },
  { term = "ndb set <name> notes <text>", definition = { "Set personal notes, including cecho colours and literal \\n line breaks. Notes survive API updates." } },
  { term = "ndb set <name> iff/importance/cityenemy/houseenemy/orderenemy <value>", definition = { "Edit personal policy only. IFF is -1 automatic, 1 enemy, 2 ally. Identity facts cannot be edited manually or imported." } },
  { term = "city/house/order enemies [add]", definition = { "Explicitly request the game enemy list and update personal flags. Add also discovers unknown names and flags them as enemies." } },
  { term = "ndb export / ndb import", definition = { "Export native records or import names and selected policy/annotation fields. Imported identity facts never override API authority." } },
  { term = "ndb delete <name> / ndb delete all / ndb delete unranked", definition = { "Delete records and cancel outstanding requests first. Bulk deletion requires confirmation; late responses cannot restore deleted rows." } },
  { term = "ndb stats", definition = { "Show known name counts and cached city populations, distinguishing unknown from rogue." } }
}
