#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

public Plugin myinfo =
{
    name        = "Director Player Scaling",
    author      = "Haze_of_dream",
    description = "Event-driven director and Tank HP scaling for high-player servers",
    version     = "1.7"
};

// =====================
// Base values (balanced for BASE survivor count)
// =====================

#define BASE_SMOKER_LIMIT    1
#define BASE_HUNTER_LIMIT    1
#define BASE_JOCKEY_LIMIT    1
#define BASE_CHARGER_LIMIT   1
#define BASE_SPITTER_LIMIT   1
#define BASE_BOOMER_LIMIT    2

#define BASE_COMMON_LIMIT    120
#define BASE_MOB_MIN         30
#define BASE_MOB_MAX         60
#define BASE_WANDERERS       30

#define BASE_SI_RESPAWN_TIME 20.0   // Expert baseline

// =====================
// ConVars
// =====================

ConVar cvBaseSurvivors;
ConVar cvMaxScaleSurvivors;
ConVar cvScaleIntensity;

// SI limits
ConVar cvSmoker;
ConVar cvHunter;
ConVar cvJockey;
ConVar cvCharger;
ConVar cvSpitter;
ConVar cvBoomer;

// Director
ConVar cvCommonLimit;
ConVar cvMobMin;
ConVar cvMobMax;
ConVar cvWanderers;

// Tank & SI respawn
ConVar cvTankHealth;
ConVar cvSIRespawn;

// =====================
// Plugin start
// =====================

public void OnPluginStart()
{
    cvBaseSurvivors = CreateConVar(
        "dps_base_survivor_count",
        "4",
        "Survivor count base values are balanced for",
        FCVAR_NOTIFY,
        true, 1.0,
        true, 10.0
    );

    cvMaxScaleSurvivors = CreateConVar(
        "dps_max_scaled_survivors",
        "10",
        "Maximum survivor count used for scaling",
        FCVAR_NOTIFY,
        true, 1.0,
        true, 16.0
    );

    cvScaleIntensity = CreateConVar(
        "dps_scale_intensity",
        "1.0",
        "Scaling intensity (1.0 = linear)",
        FCVAR_NOTIFY,
        true, 0.0,
        true, 3.0
    );

    AutoExecConfig(true, "director_player_scaling");

    // SI limits
    cvSmoker  = FindConVar("z_smoker_limit");
    cvHunter  = FindConVar("z_hunter_limit");
    cvJockey  = FindConVar("z_jockey_limit");
    cvCharger = FindConVar("z_charger_limit");
    cvSpitter = FindConVar("z_spitter_limit");
    cvBoomer  = FindConVar("z_boomer_limit");

    // Director pacing
    cvCommonLimit = FindConVar("z_common_limit");
    cvMobMin      = FindConVar("z_mob_spawn_min_size");
    cvMobMax      = FindConVar("z_mob_spawn_max_size");
    cvWanderers   = FindConVar("z_reserved_wanderers");

    // Tank & SI respawn
    cvTankHealth = FindConVar("z_tank_health");
    cvSIRespawn  = FindConVar("z_special_respawn_interval");

    // Survivor count change events
    HookEvent("player_team", Event_PlayerTeam, EventHookMode_Post);
    HookEvent("player_disconnect", Event_PlayerDisconnect, EventHookMode_Post);
    HookEvent("bot_player_replace", Event_PlayerSwap, EventHookMode_Post);
    HookEvent("player_bot_replace", Event_PlayerSwap, EventHookMode_Post);

    // Tank HP
    HookEvent("tank_spawn", Event_TankSpawn, EventHookMode_Post);

    // Initial application
    ApplyDirectorScaling();
}

// =====================
// Event handlers
// =====================

public void Event_PlayerTeam(Event event, const char[] name, bool dontBroadcast)
{
    ApplyDirectorScaling();
}

public void Event_PlayerDisconnect(Event event, const char[] name, bool dontBroadcast)
{
    ApplyDirectorScaling();
}

public void Event_PlayerSwap(Event event, const char[] name, bool dontBroadcast)
{
    ApplyDirectorScaling();
}

public void Event_TankSpawn(Event event, const char[] name, bool dontBroadcast)
{
    int tank = GetClientOfUserId(event.GetInt("userid"));
    if (!IsValidClient(tank))
        return;

    float baseHP = float(cvTankHealth.IntValue);
    float scale  = GetScalingFactor(GetSurvivorCount());

    int hp = RoundToNearest(baseHP * scale);

    SetEntProp(tank, Prop_Data, "m_iHealth", hp);
    SetEntProp(tank, Prop_Data, "m_iMaxHealth", hp);
}

// =====================
// Director scaling logic
// =====================

void ApplyDirectorScaling()
{
    int survivors = GetSurvivorCount();
    float scale = GetScalingFactor(survivors);

    int stunlockCap = survivors;

    SetConVarInt(cvSmoker,  Clamp(RoundToCeil(BASE_SMOKER_LIMIT  * scale), 1, stunlockCap));
    SetConVarInt(cvHunter,  Clamp(RoundToCeil(BASE_HUNTER_LIMIT  * scale), 1, stunlockCap));
    SetConVarInt(cvJockey,  Clamp(RoundToCeil(BASE_JOCKEY_LIMIT  * scale), 1, stunlockCap));
    SetConVarInt(cvCharger, Clamp(RoundToCeil(BASE_CHARGER_LIMIT * scale), 1, stunlockCap));

    SetConVarInt(cvSpitter, RoundToCeil(BASE_SPITTER_LIMIT * scale));
    SetConVarInt(cvBoomer,  RoundToCeil(BASE_BOOMER_LIMIT  * scale));

    SetConVarInt(cvCommonLimit, RoundToCeil(BASE_COMMON_LIMIT * scale));
    SetConVarInt(cvMobMin, RoundToCeil(BASE_MOB_MIN * scale));
    SetConVarInt(cvMobMax, RoundToCeil(BASE_MOB_MAX * scale));
    SetConVarInt(cvWanderers, RoundToCeil(BASE_WANDERERS * scale));

    // Faster SI respawns with more survivors
    float respawn = BASE_SI_RESPAWN_TIME / scale;
    if (respawn < 5.0)
        respawn = 5.0;

    SetConVarFloat(cvSIRespawn, respawn);
}

// =====================
// Scaling math (FIXED)
// =====================

float GetScalingFactor(int survivors)
{
    int base = cvBaseSurvivors.IntValue;
    int max  = cvMaxScaleSurvivors.IntValue;

    // Never scale BELOW base
    if (survivors <= base)
        return 1.0;

    if (survivors > max)
        survivors = max;

    float rawScale = float(survivors) / float(base);
    float intensity = cvScaleIntensity.FloatValue;

    return 1.0 + ((rawScale - 1.0) * intensity);
}

// =====================
// Utilities
// =====================

int GetSurvivorCount()
{
    int count = 0;
    for (int i = 1; i <= MaxClients; i++)
    {
        // Includes humans and bots
        if (IsClientInGame(i) && GetClientTeam(i) == 2)
            count++;
    }
    return count;
}

bool IsValidClient(int client)
{
    return client > 0 && client <= MaxClients && IsClientInGame(client);
}

int Clamp(int value, int min, int max)
{
    if (value < min) return min;
    if (value > max) return max;
    return value;
}