RTG Paragon Who List Bot Filter

This version moves the /who bot filter out of visual row-hiding and into a server-side preference.

What changed:
- RTG_ParagonDisplay adds a Bots: Shown / Bots: Hidden button on the upper-right area of the Who List frame.
- The button no longer hides rows client-side, so it will not leave blank spaces.
- The addon sends the player's preference to mod-paragon-levels through RTG_PARAGON addon messages.
- mod-paragon-levels stores the preference per character in character_paragon_settings.hide_who_bots.
- Apply core-patches/rtg_paragon_server_side_who_bot_filter.patch to the AzerothCore core so HandleWhoOpcode skips bot sessions before building the 50 returned Who List rows.

Install:
1. Replace mod-paragon-levels with this folder and rebuild/restart worldserver.
2. Apply core-patches/rtg_paragon_server_side_who_bot_filter.patch to your AzerothCore source, rebuild, and restart.
3. Copy addons/RTG_ParagonDisplay into the client Interface/AddOns folder.

Slash commands:
/rtgwho toggle
/rtgwho hide
/rtgwho show
/rtgwho status
/whohidebots
