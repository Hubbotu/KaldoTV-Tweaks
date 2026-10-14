# Kaldo Tweaks

`Kaldo Tweaks` is a lightweight World of Warcraft Retail addon focused on small quality-of-life improvements for group play, Mythic+, UI readability, and macro automation.

The addon is built as a modular toolbox:

- enable only the features you want
- keep CPU usage as low as possible
- avoid unnecessary UI clutter
- stay compatible with existing saved settings through versioned migrations

## Local Testing

From the repository, deploy to the default WoW Retail installation:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\deploy.ps1
```

Use `-RetailPath 'D:\Games\World of Warcraft\_retail_'` for another installation,
or `-WhatIf` to preview the destination files. The script copies runtime files
and verifies their hashes; it does not delete files or modify saved settings.
Run `/reload` in WoW afterwards. Restart WoW if the TOC file list changed.

Run the regression checks from the repository root with Lua 5.1 or newer:

```text
lua tools/test_runtime.lua
lua tools/test_equipment_info.lua
lua tools/test_mm_keys.lua
lua tools/test_castbar_style.lua
lua tools/test_quick_shortcuts.lua
```

These checks simulate the WoW APIs. In-game validation is still needed for combat restrictions and visual layout.

## Features

### Equipment Info

Adds item level and equipment status information directly on the character and inspect frames.

- item level overlay on equipped gear
- inspect item level display
- inspect average item level display
- socket checks
- enchant checks
- configurable fonts, sizes, thresholds, and colors

### Buff Check

Displays missing group buff reminders with configurable icons and highlight styles.

- supports common group buffs
- optional "only my buffs" mode
- configurable position, spacing, size, and highlight

### Pet Alert

Shows on-screen alerts when your pet is missing or dead, depending on class/spec configuration.

- separate dead/missing alerts
- per-alert font, color, sound, and position settings
- spec filtering

### Craft Order Alert

Detects system messages matching a configured text and shows an on-screen alert.

- configurable trigger text
- case sensitivity option
- throttle
- configurable text, font, color, sound, and position

### MM+ Keys

Adds a few Mythic+ quality-of-life helpers.

- auto-insert your keystone when relevant
- reply to `!key` / `!keys`
- accepted-group reminders
- optional Focus Kick marker, per-character focus/mark macro, and pre-key ready-check announcement (Mythic+ listing or inserted keystone required)
- dungeon teleport window on joining a Mythic+ group, with learned/cooldown status and a persistent opt-out in the window or settings
- season-best dungeon overlays and dungeon teleport buttons
- regional/world score percentile estimates
- optional filtering of stale guild roster scores

### Group Ready

Shows a group preparation summary, available through `/kaldoinspect`.

- member item levels, specializations, and Mythic+ scores
- group buff coverage and composition warnings
- configurable automatic display

### Blizzard Cast Bars

Customizes the default nameplate cast bars.

- separate colors for normal, important, and non-interruptible casts
- interrupt-ready glow with configurable color, speed, thickness, and segment count
- animated settings preview
- glow animation capped at 30 updates per second; a static border is used when dimensions are secret

### Auto Macros

Creates or updates utility macros based on your current group composition and known spells.

- tank mark macro
- Evoker support macros
- Hunter Misdirection macro
- Rogue Tricks macro
- Shaman Earth Shield macro

### Auto Potion

Creates or updates a self-heal / potion macro based on available items, known spells, and per-character priority.

- auto-detects configured potions and healthstones
- supports class self-heals and supported racials
- per-character priority order

## Design Goals

`Kaldo Tweaks` is built around a few simple rules:

- modular first
- readable code
- backward-compatible saved variables
- restrained CPU usage
- practical UI improvements over flashy behavior

## Slash Commands

- `/kaldo` opens the addon settings
- `/kaldostatus` prints the current module status in chat
- `/kaldoinspect` opens the Group Ready summary
- `/kaldommdebug` prints Mythic+ percentile diagnostics

## Compatibility

- WoW Retail
- uses Blizzard Settings
- optional support for `LibSharedMedia-3.0`

## Notes

- Most modules are disabled by default.
- Settings are stored in `KaldoDB`.
- Existing saved variables are migrated automatically when needed.
