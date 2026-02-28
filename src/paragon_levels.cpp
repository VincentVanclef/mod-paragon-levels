/*
 * RTG Paragon Levels (WotLK 3.3.5a / AzerothCore)
 *
 * Fixes included:
 * - Paragon cap (default 200) with unreachable next XP at cap
 * - Milestone titles at 50/100/150/200 (configurable IDs)
 * - Paragon tier chat color formatting for Paragon system messages (toggle per-character)
 * - Modern ChatCommands API (ChatCommandTable / ChatCommandBuilder) to avoid deprecated ChatCommand warnings
 * - NO "+X" name suffix logic (does not hook NAME_QUERY)
 * - Addon message responder (RTG_PARAGON) to support tooltip addon WITHOUT name parsing:
 *     Client sends:  "RTG_PARAGON\tQ:<name>"   (WHISPER, LANG_ADDON)
 *     Server replies:"RTG_PARAGON\tA:<name>:<paragon>"
 *
 * IMPORTANT NOTE ABOUT CHAT HOOKS:
 * - Your AzerothCore revision does NOT have PLAYERHOOK_ON_CHAT / PlayerScript::OnChat.
 * - So the addon responder is implemented via WorldSessionScript and intercepts CMSG_MESSAGECHAT.
 *
 * Notes:
 * - This file assumes your paragon value comes from sCurrencyHandler->GetCharacterCurrency(guid)->GetParagonLevel()
 * - This file assumes you have RewardSystem available as sRewardSystem.
 * - Per-character toggle is stored in Characters DB table: character_paragon_settings (guid PK, enable_chat_color tinyint)
 */

#include "AccountMgr.h"
#include "Chat.h"
#include "ChatCommand.h"
#include "Common.h"
#include "Config.h"
#include "DatabaseEnv.h"
#include "DBCStores.h"
#include "ObjectAccessor.h"
#include "ObjectMgr.h"
#include "Opcodes.h"
#include "Player.h"
#include "RewardSystem.h"
#include "ScriptMgr.h"
#include "World.h"
#include "WorldPacket.h"
#include "WorldSession.h"

#include <fmt/format.h>
#include <limits>
#include <string>
#include <unordered_map>
#include <vector>

namespace
{
    // Characters DB (per-character) setting for whether paragon tier colors are used in Paragon system messages.
    static constexpr char const* PARAGON_SETTINGS_TABLE = "character_paragon_settings";

    static bool LoadChatColorEnabled(uint32 guidLow, bool defaultValue)
    {
        QueryResult res = CharacterDatabase.Query(fmt::format(
            "SELECT enable_chat_color FROM `{}` WHERE guid = {} LIMIT 1",
            PARAGON_SETTINGS_TABLE, guidLow));

        if (!res)
            return defaultValue;

        Field* f = res->Fetch();
        return f[0].Get<uint8>() != 0;
    }

    static void SaveChatColorEnabled(uint32 guidLow, bool enabled)
    {
        CharacterDatabase.DirectExecute(fmt::format(
            "INSERT INTO `{}` (guid, enable_chat_color) VALUES ({}, {}) "
            "ON DUPLICATE KEY UPDATE enable_chat_color = VALUES(enable_chat_color)",
            PARAGON_SETTINGS_TABLE, guidLow, enabled ? 1 : 0));
    }

    static std::vector<std::string> SplitTab(std::string const& s)
    {
        std::vector<std::string> out;
        size_t start = 0;
        while (true)
        {
            size_t pos = s.find('\t', start);
            if (pos == std::string::npos)
            {
                out.push_back(s.substr(start));
                break;
            }
            out.push_back(s.substr(start, pos - start));
            start = pos + 1;
        }
        return out;
    }

    // Build an SMSG_MESSAGECHAT packet that matches client "addon whisper" expectations.
    // Format of payload in WotLK/AC examples is: "PREFIX\tDATA"
    static WorldPacket CreateAddonWhisperPacket(std::string const& prefix, std::string const& data, Player* receiver)
    {
        std::string full = prefix + "\t" + data;
        uint32 len = static_cast<uint32>(full.size());

        WorldPacket pkt;
        pkt.Initialize(SMSG_MESSAGECHAT, 1 + 4 + 8 + 4 + 8 + 4 + len + 1);

        pkt << uint8(CHAT_MSG_WHISPER);                      // type
        pkt << uint32(LANG_ADDON);                           // lang
        pkt << uint64(receiver->GetGUID().GetRawValue());    // sender guid (server->client, ok to use receiver guid here)
        pkt << uint32(0);                                    // flags
        pkt << uint64(receiver->GetGUID().GetRawValue());    // receiver guid
        pkt << uint32(len + 1);                              // msg length
        pkt << full;                                         // msg
        pkt << uint8(0);                                     // chat tag / null

        return pkt;
    }
}

class ParagonLevels : public PlayerScript, public WorldScript
{
public:
    ParagonLevels()
        : PlayerScript("ParagonLevels_PlayerScript",
            {
                PLAYERHOOK_ON_GET_XP_FOR_LEVEL,
                PLAYERHOOK_ON_LEVEL_CHANGED,
                PLAYERHOOK_ON_CAN_GIVE_LEVEL,
				PLAYERHOOK_ON_BEFORE_SEND_CHAT_MESSAGE
            })
        , WorldScript("ParagonLevels_WorldScript", { WORLDHOOK_ON_AFTER_CONFIG_LOAD })
    {
        s_instance = this;
    }

    static ParagonLevels* Get() { return s_instance; }

    // ------------------------------- config -------------------------------
	
	void OnPlayerBeforeSendChatMessage(Player* player, uint32& type, uint32& lang, std::string& msg) override
	{
		if (!player)
			return;

		// client addon uses: SendAddonMessage("RTG_PARAGON", "Q:<name>", "WHISPER", UnitName("player"))
		if (type != CHAT_MSG_WHISPER || lang != LANG_ADDON)
			return;

		// msg is "PREFIX\tPAYLOAD"
		auto parts = SplitTab(msg);
		if (parts.size() < 2)
			return;

		std::string const& prefix  = parts[0];
		std::string const& payload = parts[1];

		if (prefix != "RTG_PARAGON")
			return;

		// Payload: "Q:<name>"
		if (payload.rfind("Q:", 0) != 0 || payload.size() <= 2)
		{
			msg.clear();
			return;
		}

		std::string qName = payload.substr(2);

		Player* target = ObjectAccessor::FindPlayerByName(qName);
		uint32 paragon = target ? GetParagonLevel(target) : 0;

		std::string reply = fmt::format("A:{}:{}", qName, paragon);

		WorldPacket pkt = CreateAddonWhisperPacket(prefix, reply, player);
		player->SendDirectMessage(&pkt);

		// prevent further processing of this addon whisper
		msg.clear();
	}

    void OnAfterConfigLoad(bool /*reload*/) override
    {
        isEnabled = sConfigMgr->GetOption<bool>("ParagonLevel.Enable", true);
        m_xpPerLevelMod = sConfigMgr->GetOption<float>("ParagonLevel.XpPerLevelMod", 2.0f);
        m_maxParagonLevel = sConfigMgr->GetOption<uint32>("ParagonLevel.MaxParagonLevel", 200);
        defaultMaxLevel = sConfigMgr->GetOption<int32>("MaxPlayerLevel", DEFAULT_MAX_LEVEL);

        // Milestone titles
        m_titleAt50  = sConfigMgr->GetOption<uint32>("ParagonLevel.TitleAt50",  0);
        m_titleAt100 = sConfigMgr->GetOption<uint32>("ParagonLevel.TitleAt100", 0);
        m_titleAt150 = sConfigMgr->GetOption<uint32>("ParagonLevel.TitleAt150", 0);
        m_titleAt200 = sConfigMgr->GetOption<uint32>("ParagonLevel.TitleAt200", 0);

        // Paragon tier chat color strings (used in *Paragon system messages* only)
        m_colorTier0 = sConfigMgr->GetOption<std::string>("ParagonLevel.ChatColor.Tier0", "|cffFFFFFF"); // 1-49
        m_colorTier1 = sConfigMgr->GetOption<std::string>("ParagonLevel.ChatColor.Tier1", "|cff00FF7F"); // 50-99
        m_colorTier2 = sConfigMgr->GetOption<std::string>("ParagonLevel.ChatColor.Tier2", "|cff00B0FF"); // 100-149
        m_colorTier3 = sConfigMgr->GetOption<std::string>("ParagonLevel.ChatColor.Tier3", "|cffC070FF"); // 150-199
        m_colorTier4 = sConfigMgr->GetOption<std::string>("ParagonLevel.ChatColor.Tier4", "|cffFF8000"); // 200
        m_chatColorDefaultEnabled = sConfigMgr->GetOption<bool>("ParagonLevel.ChatColor.DefaultEnabled", true);

        if (isEnabled)
        {
            // Allow one extra level-up past max level to trigger our paragon hook logic
            sWorld->setIntConfig(CONFIG_MAX_PLAYER_LEVEL, defaultMaxLevel + 1);
        }
        else
        {
            sWorld->setIntConfig(CONFIG_MAX_PLAYER_LEVEL, defaultMaxLevel);
            m_cachedChatColorEnabled.clear();
        }
    }

    // ------------------------------- currency integration -------------------------------

    static uint32 GetParagonLevel(Player* player)
    {
        if (!player)
            return 0;

        if (auto currency = sCurrencyHandler->GetCharacterCurrency(player->GetGUID()))
            return currency->GetParagonLevel();

        return 0;
    }

    static uint32 IncreaseParagonLevel(Player* player)
    {
        if (!player)
            return 0;

        if (auto currency = sCurrencyHandler->GetCharacterCurrency(player->GetGUID()))
        {
            currency->ModifyParagonLevel(1);
            return currency->GetParagonLevel();
        }

        return 0;
    }

    uint32 GetXpForNextLevel(Player* player, uint32 paragonLevel) const
    {
        if (!player)
            return 0;

        if (paragonLevel >= m_maxParagonLevel)
        {
            // Make next level unreachable at cap (prevents spam/loops)
            return std::numeric_limits<uint32>::max();
        }

        if (m_xpPerLevelMod <= 1.0f)
            return sObjectMgr->GetXPForLevel(player->GetLevel());

        float mod = 1.0f + ((paragonLevel * m_xpPerLevelMod) / 100.0f);
        return static_cast<uint32>(sObjectMgr->GetXPForLevel(player->GetLevel()) * mod);
    }

    // ------------------------------- level / xp hooks -------------------------------

    bool OnPlayerCanGiveLevel(Player* player, uint8 newLevel) override
    {
        if (!isEnabled)
            return true;

        if (!player)
            return true;

        if (newLevel <= defaultMaxLevel)
            return true;

        // Ignore bots
        if (player->GetSession() && player->GetSession()->IsBot())
            return false;

        // Cap Paragon levels (default: 200)
        const uint32 currentParagon = GetParagonLevel(player);
        if (currentParagon >= m_maxParagonLevel)
        {
            const bool useColor = IsChatColorEnabled(player);
            ChatHandler(player->GetSession()).PSendSysMessage(
                "|cff00FFFFParagon Maxed:|r {}{}|r",
                useColor ? GetTierColor(m_maxParagonLevel) : "|cffFF0000",
                m_maxParagonLevel);

            player->SetUInt32Value(PLAYER_NEXT_LEVEL_XP, GetXpForNextLevel(player, m_maxParagonLevel));
            return false;
        }

        // Optional level up spell
        if (const uint32 levelUpSpell = sConfigMgr->GetOption<uint32>("ParagonLevel.LevelUpSpell", 47292))
            player->CastSpell(player, levelUpSpell, true);

        const uint32 paragonLevel = IncreaseParagonLevel(player);

        // Rewards
        sRewardSystem->HandleRewards(player, "ON_PLAYER_LEVEL_UP_PARAGON");
        if (paragonLevel % 5 == 0)
            sRewardSystem->HandleRewards(player, "ON_PLAYER_LEVEL_UP_PARAGON_5_INTERVAL");

        // Feedback
        const bool useColor = IsChatColorEnabled(player);
        std::string tierColor = useColor ? GetTierColor(paragonLevel) : std::string("|cffFF0000");
        ChatHandler(player->GetSession()).PSendSysMessage(
            "|cff00FFFFYour Paragon Level is:|r {}{}|r",
            tierColor, paragonLevel);

        // Titles at milestones
        HandleMilestoneRewards(player, paragonLevel);

        // Restore resources (optional)
        if (sConfigMgr->GetOption<bool>("ParagonLevel.RestoreStatsOnLevelUp", false))
        {
            if (!player->isDead())
            {
                player->SetFullHealth();
                player->SetPower(POWER_MANA, player->GetMaxPower(POWER_MANA));
                player->SetPower(POWER_ENERGY, player->GetMaxPower(POWER_ENERGY));
                if (player->GetPower(POWER_RAGE) > player->GetMaxPower(POWER_RAGE))
                    player->SetPower(POWER_RAGE, player->GetMaxPower(POWER_RAGE));
                player->SetPower(POWER_FOCUS, 0);
                player->SetPower(POWER_HAPPINESS, 0);
            }
        }

        // Next XP requirement based on paragon level
        player->SetUInt32Value(PLAYER_NEXT_LEVEL_XP, GetXpForNextLevel(player, paragonLevel));
        return false;
    }

    void OnPlayerGetXpForLevel(Player* player, uint32& xp) override
    {
        if (!isEnabled || !player)
            return;

        const uint32 paragonLevel = GetParagonLevel(player);
        if (paragonLevel == 0)
            return;

        xp = GetXpForNextLevel(player, paragonLevel);
    }

    // ------------------------------- toggles (per character) -------------------------------

    bool IsChatColorEnabled(Player* player)
    {
        uint32 guidLow = player->GetGUID().GetCounter();
        auto it = m_cachedChatColorEnabled.find(guidLow);
        if (it != m_cachedChatColorEnabled.end())
            return it->second;

        bool enabled = LoadChatColorEnabled(guidLow, m_chatColorDefaultEnabled);
        m_cachedChatColorEnabled[guidLow] = enabled;
        return enabled;
    }

    void SetChatColorEnabled(Player* player, bool enabled)
    {
        uint32 guidLow = player->GetGUID().GetCounter();
        m_cachedChatColorEnabled[guidLow] = enabled;
        SaveChatColorEnabled(guidLow, enabled);
    }

    std::string GetTierColor(uint32 paragonLevel) const
    {
        if (paragonLevel >= 200)
            return m_colorTier4;
        if (paragonLevel >= 150)
            return m_colorTier3;
        if (paragonLevel >= 100)
            return m_colorTier2;
        if (paragonLevel >= 50)
            return m_colorTier1;
        return m_colorTier0;
    }

    void HandleMilestoneRewards(Player* player, uint32 paragonLevel)
    {
        uint32 titleId = 0;
        if (paragonLevel == 50)  titleId = m_titleAt50;
        if (paragonLevel == 100) titleId = m_titleAt100;
        if (paragonLevel == 150) titleId = m_titleAt150;
        if (paragonLevel == 200) titleId = m_titleAt200;

        if (!titleId)
            return;

        if (CharTitlesEntry const* titleEntry = sCharTitlesStore.LookupEntry(titleId))
        {
            player->SetTitle(titleEntry);
            ChatHandler(player->GetSession()).PSendSysMessage(
                "|cff00FF00Milestone reached!|r You earned a new title at Paragon {}.",
                paragonLevel);
        }
        else
        {
            ChatHandler(player->GetSession()).PSendSysMessage(
                "|cffff0000Paragon milestone title not found in CharTitles.dbc (ID {}).|r",
                titleId);
        }
    }

private:
    bool isEnabled = false;

    float m_xpPerLevelMod = 2.0f;
    int32 defaultMaxLevel = 0;

    uint32 m_maxParagonLevel = 200;

    // Milestone title IDs
    uint32 m_titleAt50  = 0;
    uint32 m_titleAt100 = 0;
    uint32 m_titleAt150 = 0;
    uint32 m_titleAt200 = 0;

    // Tier color strings (server-side chat color formatting)
    std::string m_colorTier0;
    std::string m_colorTier1;
    std::string m_colorTier2;
    std::string m_colorTier3;
    std::string m_colorTier4;

    bool m_chatColorDefaultEnabled = true;
    std::unordered_map<uint32, bool> m_cachedChatColorEnabled;

    static ParagonLevels* s_instance;
};

ParagonLevels* ParagonLevels::s_instance = nullptr;

// --------------------------------- commands ---------------------------------

class ParagonLevelsCommands : public CommandScript
{
public:
    ParagonLevelsCommands() : CommandScript("ParagonLevelsCommands") { }

    static bool HandleParagonColor(ChatHandler* handler)
    {
        Player* player = handler->GetPlayer();
        if (!player)
            return false;

        if (auto* mod = ParagonLevels::Get())
        {
            bool enabled = mod->IsChatColorEnabled(player);
            handler->PSendSysMessage("|cff00FFFFParagon tier colors:|r {}", enabled ? "|cff00FF00ON|r" : "|cffff0000OFF|r");
            handler->PSendSysMessage("Use: .paragon color on  OR  .paragon color off");
            return true;
        }

        handler->SendSysMessage("Paragon module not loaded.");
        return true;
    }

    static bool HandleParagonColorOn(ChatHandler* handler)
    {
        Player* player = handler->GetPlayer();
        if (!player)
            return false;

        if (auto* mod = ParagonLevels::Get())
        {
            mod->SetChatColorEnabled(player, true);
            handler->SendSysMessage("|cff00FFFFParagon tier colors are now:|r |cff00FF00ON|r");
            return true;
        }
        return true;
    }

    static bool HandleParagonColorOff(ChatHandler* handler)
    {
        Player* player = handler->GetPlayer();
        if (!player)
            return false;

        if (auto* mod = ParagonLevels::Get())
        {
            mod->SetChatColorEnabled(player, false);
            handler->SendSysMessage("|cff00FFFFParagon tier colors are now:|r |cffff0000OFF|r");
            return true;
        }
        return true;
    }

    Acore::ChatCommands::ChatCommandTable GetCommands() const override
    {
        using namespace Acore::ChatCommands;

        static ChatCommandTable paragonColorSub =
        {
            ChatCommandBuilder("",    HandleParagonColor,    SEC_PLAYER, Console::No),
            ChatCommandBuilder("on",  HandleParagonColorOn,  SEC_PLAYER, Console::No),
            ChatCommandBuilder("off", HandleParagonColorOff, SEC_PLAYER, Console::No),
        };

        static ChatCommandTable paragonRoot =
        {
            ChatCommandBuilder("color", paragonColorSub),
        };

        static ChatCommandTable commands =
        {
            ChatCommandBuilder("paragon", paragonRoot),
        };

        return commands;
    }
};

void Add_ParagonLevels()
{
    new ParagonLevels();
    new ParagonLevelsCommands();
}