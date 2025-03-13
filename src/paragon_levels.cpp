#include "AccountMgr.h"
#include "Common.h"
#include "Config.h"
#include "Player.h"
#include "ScriptMgr.h"
#include "Chat.h"
#include "RewardSystem.h"

class ParagonLevels : public PlayerScript, public WorldScript
{
public:
    ParagonLevels() :
        PlayerScript("ParagonLevels_PlayerScript", { PLAYERHOOK_ON_LEVEL_CHANGED, PLAYERHOOK_ON_CAN_GIVE_LEVEL, PLAYERHOOK_ON_SEND_NAME_QUERY_OPCODE }),
        WorldScript("ParagonLevels_WorldScript", { WORLDHOOK_ON_AFTER_CONFIG_LOAD })
    {
    }

    void OnAfterConfigLoad(bool reload) override
    {
        isEnabled = sConfigMgr->GetOption<bool>("ParagonLevel.Enable", true);
        defaultMaxLevel = sConfigMgr->GetOption<int32>("MaxPlayerLevel", DEFAULT_MAX_LEVEL);
        m_PlayerNameTag = sConfigMgr->GetOption<std::string>("ParagonLevel.PlayerNameTag", " : P ");

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

    static uint32 GetParagonLevel(Player* player)
    {
        if (auto currency = sCurrencyHandler->GetCharacterCurrency(player->GetGUID()))
            return currency->GetParagonLevel();

        return 0;
    }

    static uint32 IncreaseParagonLevel(Player* player)
    {
        if (auto currency = sCurrencyHandler->GetCharacterCurrency(player->GetGUID()))
        {
            currency->ModifyParagonLevel(1);
            player->GetSession()->SendNameQueryOpcode(player->GetGUID());
            return currency->GetParagonLevel();
        }

        return 0;
    }

    bool OnPlayerCanGiveLevel(Player* player, uint8 newLevel) override
    {
        if (!isEnabled)
            return true;

        if (newLevel <= defaultMaxLevel)
            return true;

        if (const uint32 levelUpSpell = sConfigMgr->GetOption<uint32>("ParagonLevel.LevelUpSpell", 47292))
            player->CastSpell(player, levelUpSpell, true);

        const uint32 paragonLevel = IncreaseParagonLevel(player);

        sRewardSystem->HandleRewards(player, "ON_PLAYER_LEVEL_UP_PARAGON");

        if (paragonLevel % 5 == 0)
        {
            sRewardSystem->HandleRewards(player, "ON_PLAYER_LEVEL_UP_PARAGON_5_INTERVAL");
        }

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

    void OnPlayerSendNameQueryOpcode(Player* player, std::string& name) override
    {
        if (!isEnabled || !player || m_PlayerNameTag.empty())
            return;

        if (!player)
            return;

        const uint32 paragonLevel = GetParagonLevel(player);
        if (paragonLevel == 0)
            return;

        name += m_PlayerNameTag + std::to_string(paragonLevel);
    }

private:
    bool isEnabled = false;
    std::string m_PlayerNameTag = "";
    int32 defaultMaxLevel = 0;
    std::unordered_map<ObjectGuid, uint32> m_PlayerParagonLevels;
};

void Add_ParagonLevels()
{
    new ParagonLevels();
}
