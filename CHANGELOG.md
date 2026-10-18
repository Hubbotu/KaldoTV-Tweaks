v0.9.9
New features
- Quick Shortcuts: replace repair and auction mount dropdowns with checklists showing only mounts known by the character; preserve existing fixed/random choices and randomly choose among checked mounts.
- Add the Sporebearer Fungal Strider to both checklists, unchecked by default, with a reminder to assign the corresponding NPC.

v0.9.8
New features
- MM+ Keys: offer a dungeon teleport window when joining a Mythic+ group, using the listing's activity/map IDs to choose the destination.
- Show whether the teleport is learned or on cooldown; cast through a secure button and defer opening during combat.
- Add a persistent "Don't show again" checkbox and the corresponding Kaldo configuration option. Close the window after teleporting, entering the dungeon, or leaving the group.
- Fix Changelog
- MM+ Keys: add an opt-in Focus Kick setting with a choice of eight raid markers and an automatically maintained per-character KaldoFocusKick macro (focus + mark the selected enemy, without toggling the marker off).
- Announce the chosen focus kick marker at ready checks in the identified Mythic+ dungeon before the key starts. Skip active runs, combat, locked chat and repeated ready-check events; never defer an announcement.

Fix
- MM+ Keys: fix old keystone group-acceptance reminders and the dungeon teleport popup reappearing after leaving a group and then joining another manually. A genuine new acceptance through Group Finder still displays the reminder and teleport window normally.
- Focus Kick: also announce for the player starting the ready check through C_PartyInfo.DoReadyCheck and the initiator's READY_CHECK_CONFIRM, with shared event/hook deduplication and no announcement for rejected or locked requests. Use the documented C_PartyInfo.IsChallengeModeActive predicate for the party run state.
- Focus Kick: use numeric macro icon file IDs with a visible fallback, and repair missing or incorrect icons even when the macro text is unchanged.

v0.9.7
Fix
- Equipment Info: use C_Item APIs for item information, detailed item levels, and socketed gems to fix errors after upgrading to WoW 12.1.5.
- Update the TOC interface to 120105 for WoW 12.1.5 and the addon version to 0.9.6.

v0.9.5
New features
- Mage Hearthstone shortcut: add one option to prioritize Silvermoon City (Midnight), using Teleport when solo and Portal when in a party or raid, if the appropriate spell is learned and available.
- Repair mount shortcut: add the Hearthkeeper's Wandering Caravan as a fixed choice and include it in random selection when collected.

Fix
- Hearthstone shortcut: skip missing, unusable, or cooling down hearthstones; fall back to available Shaman Astral Recall, then the Personal Key to the Arcantina, according to enabled options.
- Hearthstone macro: use the same selection and fallback logic as the shortcut on each press.

v0.9.4
Fix
- Remove the Dalaran Hearthstone from the random Hearthstone rotation.

v0.9.3
Fix
- Repair Hammer macro: remove `#showtooltip` to reduce macro length and use the hammer's icon when creating or updating the macro.
- Hearthstone selection: use a fixed list of toy IDs instead of matching toy names, preventing Hearthstone card toys from entering the rotation.

v0.9.0
New features
- Quick Shortcuts: add bindable buttons for owned repair mounts and auction house Brutosaur mounts, with fixed or random selection.
- Quick Shortcuts: add a Hearthstone section with a selectable checklist of collected Hearthstone toys and the regular Hearthstone.
- Hearthstone shortcut: choose one selected Hearthstone when pressed, with optional Shaman Astral Recall and Personal Key to the Arcantina fallbacks.
- Optionally generate macros for the mount and Hearthstone shortcuts.

v0.8.4
Fix
- Equipment info treats the rank 2 Rite of the Hash'ey enchant (ID 8689) as high rank.
- Nameplate cast bars show where your interrupt will become available before the cast ends.

v0.8.3

Fix
- Cast bars: determine interrupt readiness from the public cooldown state instead of converting a potentially secret duration. Fixes missing interrupt glow in combat, with regression coverage for Survival Hunter's Muzzle, cooldown transitions, and non-interruptible casts.

v0.8.2

Fixes and performance
- Cast bars: check secret dimensions before arithmetic to prevent numeric-conversion errors; use a static border while dimensions are inaccessible and resume animation when readable.
- Cast bars: cap glow updates at 30 per second, read dimensions once per update, and avoid reapplying unchanged glow settings.
- Buff Check: coalesce event bursts into one update after 200 ms, preserving the final state instead of dropping events during the throttle window.
- Buff Check: ignore unrelated aura units, update only changed icons, and apply layout settings when options change rather than on every aura refresh.
- Equipment Info: track item and socketed-gem dependencies per slot; ignore unrelated item-data events and coalesce relevant refreshes over 100 ms.
- Equipment Info: invalidate only affected slot caches; player-only invalidation no longer invalidates inspection through a shared revision.
- Equipment Info: avoid requesting already cached item data, keep incomplete item-level results retryable, count only scheduled inspection retries, and skip deferred refreshes after module disable.
- Equipment Info: remove global replacements of Blizzard guild/PvP inspection functions that silently swallowed errors; retain existing secure inspection hooks.
- Pet Alert: subscribe to health/flags events for the pet and pet-change events for the player; preserve broader subscriptions when another active module needs them.
- Core: unregister every tracked runtime event when no longer needed, including events outside the legacy list; filter unit events per module and remove the per-dispatch tracking-table allocation.
- Auto Potion: filter item-data events to configured consumables and inventory/spec events to the player; coalesce updates over 100 ms and refresh options only while the Auto Potion panel is visible.
- Auto Potion: recheck combat and enabled state before deferred work, keeping macro changes pending until combat ends.
- MM+ Keys: replace the per-frame polling loop with coalesced refreshes on window opening, Blizzard window updates, map-data changes, and learned-spell changes; skip queued work when hidden or disabled.

Documentation and validation
- README: document Group Ready, cast bars, additional MM+ features, commands, and local test commands.
- Add regression tests for migrations, subscription cleanup, unit filtering, event bursts, combat deferral, item/gem cache invalidation, inspection isolation, and MM+ refresh lifecycle.
- Extend cast-bar tests for animation throttling, simulated secret dimensions, static-border stability, and animation recovery.
- Lua tests use simulated APIs; combat behavior and visual changes still require validation in WoW. No measured in-game CPU gain is claimed.

v0.8.0
Fix
- Kaldo Inspect is now ignoring kick and distant DPS when the group is configured as raid group
- Hide previous MM rating in guild : to prevent issue if the guild window is opened during a combat, it is now a checkbox

New feature - BETA
- You can now modify the behavior of the castbar for default nameplates


v0.7.1
Fix
- Added the new Rite of the Hash'ey enchant (Rank2) as high level enchant

v0.7.0
Updates
- Revamped the configuration panel

New feature
- Added a button in the craft panel to send a message and validate the craft order

v0.6.3
Fix
- Fix Mythic score attempting to access secret values

v0.6.2
New feature
- MM Keys: added an option to hide stale Blizzard guild roster Mythic+ scores for members last seen before the current season
- Teleport buttons : Now display if the ability is on cooldown

v0.6.1
- Build fix

v0.6.0

New Features
- MM Keys: added optional regional and world Mythic+ score percentile estimates in the Challenges window
- Release builds now generate fresh Raider.IO percentile data and daily rebuilds publish dated build tags
- MM Keys: clicking a season-best dungeon tile now casts its dungeon teleport when the teleport is known

v0.5.2

Updates
- MM Keys: updated dungeon acronyms for Midnight Season 2

v0.5.1

New Features
- Auto Macros: added smart support for the Thalassian Master Repair Hammer
- Creates a `KaldoRepair` macro based on your real Midnight Blacksmithing specialization ranks
- Optional merchant auto-repair can now skip equipped slots that your hammer can repair for free

Fixes
- Improved equipped item repair detection when Blizzard returns partial durability data

v0.5.0
Updates
- Bump TOC to 11.1.0
- Update ilvl tresholds

v0.4.3
Fixes
- Removed the MM+ realm-language chat and group-frame feature
- Fixed repeated MMKeys errors caused by scanning protected group-frame children

v0.4.2
- Bump TOC version
- New options : MM+ > See realm language on chat or frames
- Update ilvl tresholds according to 12.0.7

v0.4.1
Fixes
- Pet presence is no longer checked in frost or blood specialization for DK

v0.4.0

New Features
- MM Keys: added a custom overlay on Mythic+ season-best dungeon tiles
- MM Keys: each tile can now display a dungeon acronym, best key level, score gained, and run timer
- MM Keys: added configurable font family and size options for acronym, level, score, and timer in `/kaldo`


v0.3.10

Fixes
- MM Key chat interactions are now more defensive: only strict `!key` / `!keys` messages are handled, suspicious chat payloads are ignored, self messages are ignored, and responses are rate-limited
- Group Ready now uses the actually equipped item level for the local player, which fixes mismatches caused by the previous average source
- Equipment info average item level now follows the same equipped-item-level source as Group Ready

Enhancements
- Equipment info gem quality checks now support socketed gem item IDs directly instead of relying only on tooltip text markers
- Equipment info gem/enchant rank logic now uses a max-rank whitelist model: any socketed gem or enchant not explicitly marked as max rank is treated as low rank
- Added current max-rank gem IDs for socket quality checks
- Enhance the lisibility of  buffs on the check group window

v0.3.9

Fixes
- Equipment info enchant rank detection is now based on enchant IDs instead of volatile tooltip names/text

v0.3.8

Fixes
- Prevent Blizzard updating the average player ilvl

Updates
- Update all ilvl thresholds for Equipment info to Midnight Season 1

v0.3.7

Fixes
- Fix range check looping on errors

v0.3.6

Fixes
- Buff checks now check if any valid target is in range

v0.3.5

Fixes
- Shaman: Flametongue enchantment is now searched in both main hand (Elemental) and off hand (Enhancement)
- Shaman: Tidecaller's Guard is no longer indicated as missing on Enhancement spec, as it's a passive spell

v0.3.4

Fixes
- Disable most of the buff check during Battleground because of secret values in auras

v0.3.3

Fixes
- Added a security to prevent MM+ module from reading chat during encounters (MM+, combat mode, BG)
- Enhance buff detection

New Features
- Group check: additional window when joining a group or raid containing ilvls and buff coverage

v0.3.2

Fixes
- Earth Shield (non personal version) is now searched on anyone in the group but the shaman instead of the tank only
- Fix a filter issue when "only my buff" is unticked
- Add a new fallback when in combat/MM+: when raid buffs are glowing, they are displayed as missing
- Added a new way to highlight my own buffs
- Pet alert no longer searches a pet for mages
- Pet alert no longer searches a pet for MM Hunters

v0.3.1

Updates
- Add 12.0.5 as available version for this addon
- Revamp buff check module
- Multiple buffs added to buff check
- New checks coming soon

v0.3.0

Updates
- Global refactor (AI assisted)
- Kaldotv_tweaks is now available on GitHub

v0.2.4

Fixes
- `getKnownRacialSpellID` is now a real function to avoid unexpected behavior
- Revamped config UI to prevent some interface breaks
- `/kaldo` is now blocked when the player is in combat and waits for combat to be over

Enhancements
- Median ilvl is now managed by KaldoTweaks too, and displays a decimal ilvl with the same color code as all items
- Median ilvl is now clearer when you inspect people, and follows the same color code as all items

v0.2.3

New Features
- Auto potion
- Create a new macro `KaldoPotion`
- This macro cycles around your healing options
- Icon and tooltip will always be the first item because of Blizzard limitations

v0.2.2

Updates
- Preseason ilvl threshold update

v0.2.1

Enhancements
- Hunter macro: Misdirection now targets by default in this fallback order: Focus, Tank, Target, Pet
- No more self target: macro now tries to ignore the player and target another healer or tank if possible

v0.2.0

Midnight Pre-release Update
- Equipment info: new item level thresholds based on crafted max level in champion, hero, myth
- Very low ilvl under 259
- Low ilvl 272
- Medium ilvl under 285
- High ilvl for 285 and more
- These thresholds can still be updated from the `/kaldo` menu
- Change the max ilvl in config from 200 to 350
- Updated enchanted slots to reflect available enchantments at Midnight
- Updated socket counts to reflect available sockets at Midnight

Auto Macro Feature
- New feature to help users by creating automatically updated macros for dungeon groups
- Moved Tank Automarker to this new section
- Added automacro options for the following spells:
- Shaman: Earth Shield
- Hunter: Misdirection
- Rogue: Tricks of the Trade
- Evoker: Source of Magic
- Evoker: Blistering Scales
- A macro combining the two buffs for Evokers is also available

v0.1.6-beta

Fixes
- Disabled buff check during MM+ keys
- Removed debug mode options
- Purged LFG cache to avoid misleading messages when joining a new group

v0.1.5-beta

New Features
- Create a macro to automark tanks in dungeon groups
- Remind which group you applied to on LFG when you join a group

v0.1.4-beta

Fixes
- New attempt to fix the crash when people are talking in party channel during a MM+ dungeon
- Inventory ilvl now refreshes when an item, gem, or enchant changes, without closing and reopening the tab

v0.1.3-beta

Fixes
- MM Key module should no longer try to read chat during a MM+ run

v0.1.2-beta

Fixes
- MM+ chat scan is now disabled during MM+
