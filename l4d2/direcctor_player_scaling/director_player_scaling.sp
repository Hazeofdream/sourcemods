#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

public Plugin myinfo =
{
    name        = "Director Player Scaling",
    author      = "Haze_of_dream",
    description = "Director & Tank scaling anchored to a base survivor count",
    version     = "1.5"
};

// =====================
// Base values (balanced for BASE_SURVIVORS)
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

#define BASE_TANK_HP         7000

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

// =====================
// Plugin start
// =====================

public void OnPluginStart()
{
    cvBaseSurvivors = CreateConVar(
        "dps_base_survivor_count",
        "4",
        "Survivor count the base #define values are balanced for",
        FCVAR_NOTIFY,
        true, 1.0,
        true, 10.0
    );

    cvMaxScaleSurvivors = CreateConVar(
        "dps_max_scaled_survivors",
        "8",
        "Maximum survivor count used for scaling",
        FCVAR_NOTIFY,
        true, 1.0,
        true, 16.0
    );

    cvScaleIntensity = CreateConVar(
        "dps_scale_intensity",
        "1.0",
        "Scaling intensity (1.0 = linear from base)",
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

    // Director
    cvCommonLimit = FindConVar("z_common_limit");
    cvMobMin      = FindConVar("z_mob_spawn_min_size");
    cvMobMax      = FindConVar("z_mob_spawn_max_size");
    cvWanderers   = FindConVar("z_reserved_wanderers");

    HookEvent("tank_spawn", Event_TankSpawn, EventHookMode_Post);

    CreateTimer(5.0, UpdateDirectorValues,
        _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

// =====================
// Director scaling
// =====================

public Action UpdateDirectorValues(Handle timer)
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

    return Plugin_Continue;
}

// =====================
// Tank HP scaling
// =====================

public void Event_TankSpawn(Event event, const char[] name, bool dontBroadcast)
{
    int tank = GetClientOfUserId(event.GetInt("userid"));
    if (!IsValidClient(tank))
        return;

    float scale = GetScalingFactor(GetSurvivorCount());
    int hp = RoundToNearest(BASE_TANK_HP * scale);

    SetEntProp(tank, Prop_Data, "m_iHealth", hp);
    SetEntProp(tank, Prop_Data, "m_iMaxHealth", hp);
}

// =====================
// Scaling logic (CORRECTED)
// =====================

float GetScalingFactor(int survivors)
{
    int base = cvBaseSurvivors.IntValue;
    int max  = cvMaxScaleSurvivors.IntValue;

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