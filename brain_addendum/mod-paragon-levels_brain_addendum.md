# mod-paragon-levels brain addendum

## Revision focus
This pass turns `mod-paragon-levels` into a live Scoreboard 2.x telemetry producer for milestone progression.

## What changed
- Added a lightweight scoreboard telemetry sink inside the module.
- Live milestone events now publish directly to `characters.rtg_scoreboard_events`.
- Published milestones are: `25, 50, 75, 100, 125, 150, 175, 200`.
- The emitted event type is `PARAGON_LEVEL`.
- The emitted source key is `paragon:<guid>:<milestone>` so seeded imports and live writes can safely coexist.

## Why this change happened
Scoreboard 2.0.1 could seed Paragon history from `custom_paragon_levels`, but that was only a first-seen reconstruction because the source table does not store milestone timestamps. This revision closes that gap for all future progression by publishing milestones live at the exact moment they are reached.

## Runtime behavior
When a player gains a Paragon level:
1. the module increments the player's Paragon state
2. milestone titles/rewards continue to process normally
3. if the new level matches a telemetry milestone threshold, a live scoreboard event is inserted

## Telemetry contract
- Event type: `PARAGON_LEVEL`
- Value1: milestone level reached
- Text shape: `Reached Paragon <level>`
- Source key: `paragon:<guid>:<milestone>`

## Design note
This module only emits milestone-grade telemetry, not every single Paragon level, to keep the shared activity ledger meaningful and low-noise for players.
