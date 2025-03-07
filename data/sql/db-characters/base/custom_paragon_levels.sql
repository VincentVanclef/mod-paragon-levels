DROP TABLE IF EXISTS custom_paragon_levels;

CREATE TABLE custom_paragon_levels (
    Guid INT UNSIGNED NOT NULL,
    Level INT UNSIGNED NOT NULL DEFAULT 0,
    PRIMARY KEY (Guid)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;