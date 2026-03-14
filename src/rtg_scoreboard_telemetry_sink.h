#ifndef RTG_SCOREBOARD_TELEMETRY_SINK_H
#define RTG_SCOREBOARD_TELEMETRY_SINK_H

#include "Config.h"
#include "DatabaseEnv.h"
#include "Player.h"

#include <ctime>
#include <string>

namespace RTG::ScoreboardTelemetrySink
{
    enum EventType : uint16
    {
        GURUBASHI_CHEST = 1,
        BG_WIN = 2,
        ARENA_WIN = 3,
        PARAGON_LEVEL = 4,
        WORLD_OBJECTIVE = 5,
        TRANSMOG_UNLOCK = 6,
        SLOT_MACHINE_JACKPOT = 7,
        REALM_MILESTONE = 8,
    };

    inline bool Enabled()
    {
        return sConfigMgr->GetOption<bool>("RTG.Scoreboard.Telemetry.Enable", true);
    }

    inline bool TableExists(char const* tableName)
    {
        QueryResult r = CharacterDatabase.Query("SHOW TABLES LIKE '{}'", tableName);
        return bool(r);
    }

    inline std::string Escape(std::string value)
    {
        CharacterDatabase.EscapeString(value);
        return value;
    }

    inline void LogEvent(uint16 eventType, uint32 playerGuid, std::string const& playerName, uint8 team, uint32 value1 = 0, uint32 value2 = 0, std::string text = "", std::string sourceKey = "")
    {
        if (!Enabled() || !TableExists("rtg_scoreboard_events"))
            return;

        if (sourceKey.empty())
        {
            CharacterDatabase.Execute(
                "INSERT INTO `rtg_scoreboard_events` (`timestamp`, `event_type`, `player_guid`, `player_name`, `team`, `value1`, `value2`, `text`, `source_key`) VALUES ({}, {}, {}, '{}', {}, {}, {}, '{}', NULL)",
                uint32(std::time(nullptr)),
                uint32(eventType),
                playerGuid,
                Escape(playerName),
                uint32(team),
                value1,
                value2,
                Escape(text));
            return;
        }

        CharacterDatabase.Execute(
            "INSERT IGNORE INTO `rtg_scoreboard_events` (`timestamp`, `event_type`, `player_guid`, `player_name`, `team`, `value1`, `value2`, `text`, `source_key`) VALUES ({}, {}, {}, '{}', {}, {}, {}, '{}', '{}')",
            uint32(std::time(nullptr)),
            uint32(eventType),
            playerGuid,
            Escape(playerName),
            uint32(team),
            value1,
            value2,
            Escape(text),
            Escape(sourceKey));
    }

    inline void LogEvent(uint16 eventType, Player* player, uint32 value1 = 0, uint32 value2 = 0, std::string text = "", std::string sourceKey = "")
    {
        if (!player)
            return;

        LogEvent(eventType, player->GetGUID().GetCounter(), player->GetName(), uint8(player->GetTeamId()), value1, value2, text, sourceKey);
    }
}

#endif
