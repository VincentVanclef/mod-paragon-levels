-- Per-character preferences for Paragon visuals
-- This is used by mod-paragon-levels to let each player toggle Paragon tier colors in chat messages.

CREATE TABLE IF NOT EXISTS `character_paragon_settings` (
  `guid` INT UNSIGNED NOT NULL,
  `enable_chat_color` TINYINT UNSIGNED NOT NULL DEFAULT 1,
  PRIMARY KEY (`guid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
