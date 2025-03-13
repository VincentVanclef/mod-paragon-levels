UPDATE character_currencies set ParagonLevel = 0;
UPDATE character_currencies cc
JOIN custom_paragon_levels cpl ON cc.guid = cpl.guid
SET cc.ParagonLevel = cpl.level;