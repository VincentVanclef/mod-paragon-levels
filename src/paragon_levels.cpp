#include "AccountMgr.h"
#include "Common.h"
#include "Config.h"
#include "Player.h"
#include "ScriptMgr.h"
#include "Chat.h"

class ParagonLevels : public PlayerScript, public WorldScript
{
public:
    ParagonLevels() :
        PlayerScript("ParagonLevels_PlayerScript", { PLAYERHOOK_ON_LEVEL_CHANGED, PLAYERHOOK_ON_BEFORE_LEVEL_CHANGED, PLAYERHOOK_ON_LOGIN, PLAYERHOOK_ON_LOGOUT }),
        WorldScript("ParagonLevels_WorldScript", { WORLDHOOK_ON_AFTER_CONFIG_LOAD })
    {
    }

    void OnAfterConfigLoad(bool reload) override
    {
        isEnabled = sConfigMgr->GetOption<bool>("ParagonLevel.Enable", true);
        defaultMaxLevel = sConfigMgr->GetOption<int32>("MaxPlayerLevel", DEFAULT_MAX_LEVEL);

        if (isEnabled)
        {
            // Increase max player level by 1
            sWorld->setIntConfig(CONFIG_MAX_PLAYER_LEVEL, defaultMaxLevel + 1);
        }
        else
        {
            // Reset max player level
            sWorld->setIntConfig(CONFIG_MAX_PLAYER_LEVEL, defaultMaxLevel);

            m_PlayerParagonLevels.clear();
        }
    }

    void OnPlayerLogin(Player* player) override
    {
        if (!isEnabled)
            return;

        if (QueryResult result = CharacterDatabase.Query("SELECT Level FROM custom_paragon_levels WHERE Guid = '{}'", player->GetGUID().GetCounter()))
        {
            uint32 level = (*result)[0].Get<uint32>();
            m_PlayerParagonLevels[player->GetGUID()] = level;
        }
        else
            m_PlayerParagonLevels[player->GetGUID()] = 0;
    }

    void OnPlayerLogout(Player* player) override
    {
        if (!isEnabled)
            return;

        auto itr = m_PlayerParagonLevels.find(player->GetGUID());
        if (itr != m_PlayerParagonLevels.end())
            m_PlayerParagonLevels.erase(itr);
    }

    uint32 GetParagonLevel(Player* player)
    {
        auto itr = m_PlayerParagonLevels.find(player->GetGUID());
        if (itr != m_PlayerParagonLevels.end())
            return itr->second;

        return 0;
    }

    uint32 IncreaseParagonLevel(Player* player)
    {
        uint32& paragonLevel = m_PlayerParagonLevels[player->GetGUID()];

        ++paragonLevel;

        CharacterDatabase.Execute("REPLACE INTO custom_paragon_levels (Guid, Level) VALUES ('{}', '{}')", player->GetGUID().GetCounter(), paragonLevel);

        return paragonLevel;
    }

    bool OnPlayerCanChangeLevel(Player* player, uint8 newLevel) override
    {
        if (!isEnabled)
            return true;

        if (newLevel <= defaultMaxLevel)
            return true;

        if (const uint32 levelUpSpell = sConfigMgr->GetOption<uint32>("ParagonLevel.LevelUpSpell", 47292))
            player->CastSpell(player, levelUpSpell, true);

        const uint32 paragonLevel = IncreaseParagonLevel(player);

#ifdef REWARDSYSTEM_MODULE
        sRewardSystem->HandleRewards(player, "ON_PLAYER_LEVEL_UP_PARAGON");

        if (player->GetCurrency()->GetParagonLevel() % 5 == 0)
        {
            sRewardSystem->HandleRewards(player, "ON_PLAYER_LEVEL_UP_PARAGON_5_INTERVAL");
        }
#endif

        ChatHandler(player->GetSession()).PSendSysMessage("|cff00FFFFYour Paragon Level is:|r |cffFF0000{}|r", paragonLevel);

        if (sConfigMgr->GetOption<bool>("ParagonLevel.RestoreStatsOnLevelUp", false))
        {
            if (!player->isDead())
            {
                // set current level health and mana/energy to maximum after applying all mods.
                player->SetFullHealth();
                player->SetPower(POWER_MANA, player->GetMaxPower(POWER_MANA));
                player->SetPower(POWER_ENERGY, player->GetMaxPower(POWER_ENERGY));
                if (player->GetPower(POWER_RAGE) > player->GetMaxPower(POWER_RAGE))
                    player->SetPower(POWER_RAGE, player->GetMaxPower(POWER_RAGE));
                player->SetPower(POWER_FOCUS, 0);
                player->SetPower(POWER_HAPPINESS, 0);
            }
        }

        player->SetUInt32Value(PLAYER_NEXT_LEVEL_XP, sObjectMgr->GetXPForLevel(player->GetLevel()));

        return false;
    }

private:
    bool isEnabled = false;
    int32 defaultMaxLevel = 0;
    std::unordered_map<ObjectGuid, uint32> m_PlayerParagonLevels;
};

void Add_ParagonLevels()
{
    new ParagonLevels();
}
