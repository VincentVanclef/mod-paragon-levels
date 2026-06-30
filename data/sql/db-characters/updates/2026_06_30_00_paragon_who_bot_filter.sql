CREATE TABLE IF NOT EXISTS `character_paragon_settings` (
  `guid` INT UNSIGNED NOT NULL,
  `enable_chat_color` TINYINT UNSIGNED NOT NULL DEFAULT 1,
  `hide_who_bots` TINYINT UNSIGNED NOT NULL DEFAULT 0,
  PRIMARY KEY (`guid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

SET @rtg_paragon_has_hide_who_bots := (
  SELECT COUNT(*)
  FROM INFORMATION_SCHEMA.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'character_paragon_settings'
    AND COLUMN_NAME = 'hide_who_bots'
);

SET @rtg_paragon_sql := IF(
  @rtg_paragon_has_hide_who_bots = 0,
  'ALTER TABLE `character_paragon_settings` ADD COLUMN `hide_who_bots` TINYINT UNSIGNED NOT NULL DEFAULT 0 AFTER `enable_chat_color`',
  'SELECT 1'
);

PREPARE rtg_paragon_stmt FROM @rtg_paragon_sql;
EXECUTE rtg_paragon_stmt;
DEALLOCATE PREPARE rtg_paragon_stmt;
