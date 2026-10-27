#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

public Plugin myinfo =
{
    name        = "Director Player Scaling",
    author      = "Haze_of_dream",
    description = "Event-driven director and Tank HP scaling for high-player servers",
    version     = "2.0"
};

// =====================
// Base values
// =====================

#define BASE_SMOKER_LIMIT    1
#define BASE_HUNTER_LIMIT    1
#define BASE_JOCKEY_LIMIT    1
#define BASE_CHARGER_LIMIT   1
#define BASE_SPITTER_LIMIT   1
#define BASE_BOOMER_LIMIT    1

#define BASE_COMMON_LIMIT    30
#define BASE_MOB_MIN         10
#define BASE_MOB_MAX         25
#define BASE_WANDERERS       10

#define BASE_SI_RESPAWN_TIME 60.0

#define TEAM_SPECTATOR       1
#define TEAM_SURVIVOR        2

// Delay before recounting, so team changes / disconnects have fully applied
// and bursts of events collapse into a single update.
#define RESCALE_DELAY        0.5

// =====================
// ConVars
// =====================

ConVar cvBaseSurvivors;
ConVar cvMaxScaleSurvivors;
ConVar cvScaleIntensity;
ConVar cvMinScale;
ConVar cvBaseTankHealth;

Handle g_hRescaleTimer = null;

// =====================
// Plugin start
// =====================

public void OnPluginStart()
{
    cvBaseSurvivors = CreateConVar(
        "dps_base_survivor_count",
        "1",
        "Human survivor count base values are balanced for",
        FCVAR_NOTIFY,
        true, 1.0,
        true, 10.0
    );

    cvMaxScaleSurvivors = CreateConVar(
        "dps_max_scaled_survivors",
        "8",
        "Maximum human survivor count used for scaling",
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

    cvMinScale = CreateConVar(
        "dps_min_scale",
        "0.25",
        "Lowest scale used when fewer humans than dps_base_survivor_count are playing",
        FCVAR_NOTIFY,
        true, 0.05,
        true, 1.0
    );

    cvBaseTankHealth = CreateConVar(
        "dps_base_tank_health",
        "7000",
        "Unscaled z_tank_health (game difficulty multiplier is applied on top)",
        FCVAR_NOTIFY,
        true, 1.0
    );

    AutoExecConfig(true, "director_player_scaling");

    cvBaseSurvivors.AddChangeHook(OnScalingCvarChanged);
    cvMaxScaleSurvivors.AddChangeHook(OnScalingCvarChanged);
    cvScaleIntensity.AddChangeHook(OnScalingCvarChanged);
    cvMinScale.AddChangeHook(OnScalingCvarChanged);
    cvBaseTankHealth.AddChangeHook(OnScalingCvarChanged);

    HookEvent("player_team", Event_Rescale, EventHookMode_PostNoCopy);
    HookEvent("bot_player_replace", Event_Rescale, EventHookMode_PostNoCopy);
    HookEvent("player_bot_replace", Event_Rescale, EventHookMode_PostNoCopy);
    HookEvent("round_start", Event_Rescale, EventHookMode_PostNoCopy);

    ApplyDirectorScaling();
}

public void OnConfigsExecuted()
{
    ApplyDirectorScaling();
}

public void OnMapEnd()
{
    // Timer is created with TIMER_FLAG_NO_MAPCHANGE and is killed on map change.
    g_hRescaleTimer = null;
}

public void OnClientDisconnect_Post(int client)
{
    QueueRescale();
}

// =====================
// Event handlers
// =====================

public void Event_Rescale(Event event, const char[] name, bool dontBroadcast)
{
    QueueRescale();
}

public void OnScalingCvarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    QueueRescale();
}

void QueueRescale()
{
    if (g_hRescaleTimer != null)
        return;

    g_hRescaleTimer = CreateTimer(RESCALE_DELAY, Timer_Rescale, _, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_Rescale(Handle timer)
{
    g_hRescaleTimer = null;
    ApplyDirectorScaling();
    return Plugin_Stop;
}

// =====================
// Director scaling logic
// =====================

void ApplyDirectorScaling()
{
    int survivors = GetHumanSurvivorCount();

    // Don't scale while no humans are on the survivor team yet.
    if (survivors <= 0)
    {
        PrintToServer("[Director Scaling] No human survivors found, skipping update.");
        return;
    }

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

    // Scaling the cvar (rather than the Tank entity) keeps the difficulty
    // multiplier intact and avoids re-healing the Tank on control passes.
    int tankHP = RoundToNearest(cvBaseTankHealth.FloatValue * scale);

    SetDirectorCvarInt("z_smoker_limit", smoker);
    SetDirectorCvarInt("z_hunter_limit", hunter);
    SetDirectorCvarInt("z_jockey_limit", jockey);
    SetDirectorCvarInt("z_charger_limit", charger);

    SetDirectorCvarInt("z_spitter_limit", spitter);
    SetDirectorCvarInt("z_boomer_limit", boomer);

    SetDirectorCvarInt("z_common_limit", commons);
    SetDirectorCvarInt("z_mob_spawn_min_size", mobMin);
    SetDirectorCvarInt("z_mob_spawn_max_size", mobMax);
    SetDirectorCvarInt("z_reserved_wanderers", wanderers);

    SetDirectorCvarFloat("z_special_spawn_interval", respawn);

    SetDirectorCvarInt("z_tank_health", tankHP);

    PrintToServer(
        "[Director Scaling] Humans=%d Scale=%.2f | Smoker=%d Hunter=%d Jockey=%d Charger=%d Spitter=%d Boomer=%d | Commons=%d Mob=%d-%d Wanderers=%d Respawn=%.1f | TankHP=%d",
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
        respawn,
        tankHP
    );
}

// =====================
// Silent ConVar wrappers
// =====================

void SetDirectorCvarInt(const char[] name, int value)
{
    ConVar cvar = FindConVar(name);

    if (cvar == null)
        return;

    int flags = cvar.Flags;

    cvar.Flags &= ~FCVAR_CHEAT;
    cvar.IntValue = value;
    cvar.Flags = flags;
}

void SetDirectorCvarFloat(const char[] name, float value)
{
    ConVar cvar = FindConVar(name);

    if (cvar == null)
        return;

    int flags = cvar.Flags;

    cvar.Flags &= ~FCVAR_CHEAT;
    cvar.FloatValue = value;
    cvar.Flags = flags;
}

// =====================
// Scaling math
// =====================

// Base values are balanced for dps_base_survivor_count humans: fewer humans scale them down
// (never below dps_min_scale), more humans scale them up (capped at dps_max_scaled_survivors).
float GetScalingFactor(int survivors)
{
    int base = cvBaseSurvivors.IntValue;
    int max  = cvMaxScaleSurvivors.IntValue;

    if (survivors > max)
        survivors = max;

    float rawScale = float(survivors) / float(base);
    float intensity = cvScaleIntensity.FloatValue;

    float scale = 1.0 + ((rawScale - 1.0) * intensity);

    float minScale = cvMinScale.FloatValue;
    if (scale < minScale)
        scale = minScale;

    return scale;
}

// =====================
// Utilities
// =====================

// Counts human survivors only. Idle humans (whose survivor is temporarily
// bot-controlled) still count; plain filler bots do not.
int GetHumanSurvivorCount()
{
    int count = 0;

    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientInGame(i) || GetClientTeam(i) != TEAM_SURVIVOR)
            continue;

        if (!IsFakeClient(i) || HasIdlePlayer(i))
            count++;
    }

    return count;
}

bool HasIdlePlayer(int bot)
{
    char netClass[16];
    if (!GetEntityNetClass(bot, netClass, sizeof(netClass)) || !StrEqual(netClass, "SurvivorBot"))
        return false;

    int human = GetClientOfUserId(GetEntProp(bot, Prop_Send, "m_humanSpectatorUserID"));

    return IsValidClient(human)
        && !IsFakeClient(human)
        && GetClientTeam(human) == TEAM_SPECTATOR;
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