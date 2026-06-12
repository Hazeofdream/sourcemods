#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

public Plugin myinfo =
{
    name        = "Director Player Scaling",
    author      = "Haze_of_dream",
    description = "Event-driven director and Tank HP scaling for high-player servers",
    version     = "1.8"
};

// =====================
// Base values
// =====================

#define BASE_SMOKER_LIMIT    1
#define BASE_HUNTER_LIMIT    1
#define BASE_JOCKEY_LIMIT    1
#define BASE_CHARGER_LIMIT   1
#define BASE_SPITTER_LIMIT   1
#define BASE_BOOMER_LIMIT    2

#define BASE_COMMON_LIMIT    120
#define BASE_MOB_MIN         20
#define BASE_MOB_MAX         50
#define BASE_WANDERERS       30

#define BASE_SI_RESPAWN_TIME 20.0

// =====================
// ConVars
// =====================

ConVar cvBaseSurvivors;
ConVar cvMaxScaleSurvivors;
ConVar cvScaleIntensity;

ConVar cvTankHealth;

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
        "281",
        "Maximum survivor count used for scaling",
        FCVAR_NOTIFY,
        true, 1.0,
        true, 31.0
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

    cvTankHealth = FindConVar("z_tank_health");

    HookEvent("player_team", Event_PlayerTeam, EventHookMode_Post);
    HookEvent("player_disconnect", Event_PlayerDisconnect, EventHookMode_Post);
    HookEvent("bot_player_replace", Event_PlayerSwap, EventHookMode_Post);
    HookEvent("player_bot_replace", Event_PlayerSwap, EventHookMode_Post);

    HookEvent("tank_spawn", Event_TankSpawn, EventHookMode_Post);

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

    float baseHP = 4000.0;

    if (cvTankHealth != null)
        baseHP = float(cvTankHealth.IntValue);

    float scale = GetScalingFactor(GetSurvivorCount());

    int hp = RoundToNearest(baseHP * scale);

    SetEntProp(tank, Prop_Data, "m_iHealth", hp);
    SetEntProp(tank, Prop_Data, "m_iMaxHealth", hp);

    PrintToServer(
        "[Director Scaling] Tank spawned with %d HP (base %.0f, scale %.2f)",
        hp,
        baseHP,
        scale
    );
}

// =====================
// Director scaling logic
// =====================

void ApplyDirectorScaling()
{
    int survivors = GetSurvivorCount();
    float scale = GetScalingFactor(survivors);

    int stunlockCap = survivors;

    int smoker     = Clamp(RoundToCeil(BASE_SMOKER_LIMIT  * scale), 1, stunlockCap);
    int hunter     = Clamp(RoundToCeil(BASE_HUNTER_LIMIT  * scale), 1, stunlockCap);
    int jockey     = Clamp(RoundToCeil(BASE_JOCKEY_LIMIT  * scale), 1, stunlockCap);
    int charger    = Clamp(RoundToCeil(BASE_CHARGER_LIMIT * scale), 1, stunlockCap);

    int spitter    = RoundToCeil(BASE_SPITTER_LIMIT * scale);
    int boomer     = RoundToCeil(BASE_BOOMER_LIMIT * scale);

    int commons    = RoundToCeil(BASE_COMMON_LIMIT * scale);
    int mobMin     = RoundToCeil(BASE_MOB_MIN * scale);
    int mobMax     = RoundToCeil(BASE_MOB_MAX * scale);
    int wanderers  = RoundToCeil(BASE_WANDERERS * scale);

    float respawn = BASE_SI_RESPAWN_TIME / scale;
    if (respawn < 5.0)
        respawn = 5.0;

    SetSMCvarInt("z_smoker_limit", smoker);
    SetSMCvarInt("z_hunter_limit", hunter);
    SetSMCvarInt("z_jockey_limit", jockey);
    SetSMCvarInt("z_charger_limit", charger);

    SetSMCvarInt("z_spitter_limit", spitter);
    SetSMCvarInt("z_boomer_limit", boomer);

    SetSMCvarInt("z_common_limit", commons);
    SetSMCvarInt("z_mob_spawn_min_size", mobMin);
    SetSMCvarInt("z_mob_spawn_max_size", mobMax);
    SetSMCvarInt("z_reserved_wanderers", wanderers);

    SetSMCvarFloat("z_special_spawn_interval", respawn);

    PrintToServer(
        "[Director Scaling] Survivors=%d Scale=%.2f | Smoker=%d Hunter=%d Jockey=%d Charger=%d Spitter=%d Boomer=%d | Commons=%d Mob=%d-%d Wanderers=%d Respawn=%.1f",
        survivors,
        scale,
        smoker,
        hunter,
        jockey,
        charger,
        spitter,
        boomer,
        commons,
        mobMin,
        mobMax,
        wanderers,
        respawn
    );
}

// =====================
// sm_cvar wrappers
// =====================

void SetSMCvarInt(const char[] cvar, int value)
{
    ServerCommand("sm_cvar %s %d", cvar, value);
}

void SetSMCvarFloat(const char[] cvar, float value)
{
    ServerCommand("sm_cvar %s %.2f", cvar, value);
}

// =====================
// Scaling math
// =====================

float GetScalingFactor(int survivors)
{
    int base = cvBaseSurvivors.IntValue;
    int max  = cvMaxScaleSurvivors.IntValue;

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
        if (IsClientInGame(i) && GetClientTeam(i) == 2)
            count++;
    }

    return count;
}

bool IsValidClient(int client)
{
    return client > 0
        && client <= MaxClients
        && IsClientInGame(client);
}

int Clamp(int value, int min, int max)
{
    if (value < min)
        return min;

    if (value > max)
        return max;

    return value;
}