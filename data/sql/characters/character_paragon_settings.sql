-- Per-character preferences for Paragon visuals and Who List visibility.
-- This is used by mod-paragon-levels to let each player toggle Paragon tier colors
-- and whether bot characters appear in their /who results.

CREATE TABLE IF NOT EXISTS `character_paragon_settings` (
  `guid` INT UNSIGNED NOT NULL,
  `enable_chat_color` TINYINT UNSIGNED NOT NULL DEFAULT 1,
  `hide_who_bots` TINYINT UNSIGNED NOT NULL DEFAULT 0,
  PRIMARY KEY (`guid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
