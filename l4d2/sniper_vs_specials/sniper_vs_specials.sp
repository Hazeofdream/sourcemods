#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdkhooks>
#include <sdktools>

/* =========================
   SI Disable Bitmask
========================= */
#define SI_SMOKER   (1 << 0)
#define SI_BOOMER   (1 << 1)
#define SI_HUNTER   (1 << 2)
#define SI_SPITTER  (1 << 3)
#define SI_JOCKEY   (1 << 4)
#define SI_CHARGER  (1 << 5)
#define SI_TANK     (1 << 6)

/* =========================
   Weapon Bitmask
========================= */
#define WPN_SCOUT   (1 << 0)
#define WPN_AWP     (1 << 1)

/* =========================
   Gamemode Bitmask
========================= */
#define MODE_COOP       (1 << 0) // 1
#define MODE_SURVIVAL   (1 << 1) // 2
#define MODE_VERSUS     (1 << 2) // 4
#define MODE_SCAVENGE   (1 << 3) // 8

ConVar g_hSIDisable;
ConVar g_hWeaponMask;
ConVar g_hModeMask;
ConVar g_hGameMode;

int g_iSIDisable;
int g_iWeaponMask;
int g_iModeMask;

public Plugin myinfo =
{
    name        = "Sniper VS Specials",
    author      = "Haze_of_dream",
    description = "Sniper Rifles Instantly kill certain special infected.",
    version     = "1.7",
    url         = ""
};

public void OnPluginStart()
{
    g_hSIDisable = CreateConVar(
        "svs_disable",
        "64",
        "1=Smoker 2=Boomer 4=Hunter 8=Spitter 16=Jockey 32=Charger 64=Tank (Add Together to disable being affected, 0=all, 127=none)",
        FCVAR_NOTIFY
    );

    g_hWeaponMask = CreateConVar(
        "svs_weapon",
        "3",
        "Affected snipers: 1=Scout 2=AWP",
        FCVAR_NOTIFY
    );

    g_hModeMask = CreateConVar(
        "svs_mode",
        "0",
        "Enable modes: 0=All, 1=Coop, 2=Survival, 4=Versus, 8=Scavenge",
        FCVAR_NOTIFY
    );

    // Auto-generate cfg/sourcemod/sniper_vs_specials.cfg
    AutoExecConfig(true, "sniper_vs_specials");

    g_hGameMode = FindConVar("mp_gamemode");

    CacheCvars();
    HookConVarChange(g_hSIDisable,  OnCvarChanged);
    HookConVarChange(g_hWeaponMask, OnCvarChanged);
    HookConVarChange(g_hModeMask,   OnCvarChanged);

    HookEvent("player_spawn", Event_PlayerSpawn, EventHookMode_Post);
}

public void OnCvarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    CacheCvars();
}

void CacheCvars()
{
    g_iSIDisable  = g_hSIDisable.IntValue;
    g_iWeaponMask = g_hWeaponMask.IntValue;
    g_iModeMask   = g_hModeMask.IntValue;
}

bool IsModeAllowed()
{
    if (g_iModeMask == 0)
        return true;

    char mode[32];
    g_hGameMode.GetString(mode, sizeof(mode));

    if (StrEqual(mode, "coop"))
        return (g_iModeMask & MODE_COOP) != 0;

    if (StrEqual(mode, "survival"))
        return (g_iModeMask & MODE_SURVIVAL) != 0;

    if (StrEqual(mode, "versus"))
        return (g_iModeMask & MODE_VERSUS) != 0;

    if (StrEqual(mode, "scavenge"))
        return (g_iModeMask & MODE_SCAVENGE) != 0;

    return false;
}

public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (IsValidClient(client))
    {
        SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
    }
}

public Action OnTakeDamage(
    int victim,
    int &attacker,
    int &inflictor,
    float &damage,
    int &damagetype)
{
    if (!IsModeAllowed())
        return Plugin_Continue;

    if (!IsValidClient(victim) || !IsValidClient(attacker))
        return Plugin_Continue;

    if (GetClientTeam(victim) != 3 || GetClientTeam(attacker) != 2)
        return Plugin_Continue;

    int zclass = GetEntProp(victim, Prop_Send, "m_zombieClass");
    int siFlag;

    if      (zclass == 1) siFlag = SI_SMOKER;
    else if (zclass == 2) siFlag = SI_BOOMER;
    else if (zclass == 3) siFlag = SI_HUNTER;
    else if (zclass == 4) siFlag = SI_SPITTER;
    else if (zclass == 5) siFlag = SI_JOCKEY;
    else if (zclass == 6) siFlag = SI_CHARGER;
    else if (zclass == 8) siFlag = SI_TANK;
    else return Plugin_Continue;

    if (g_iSIDisable & siFlag)
        return Plugin_Continue;

    int weapon = GetEntPropEnt(attacker, Prop_Send, "m_hActiveWeapon");
    if (weapon <= MaxClients || !IsValidEntity(weapon))
        return Plugin_Continue;

    char classname[64];
    GetEntityClassname(weapon, classname, sizeof(classname));

    int weaponFlag;
    if      (StrEqual(classname, "weapon_sniper_scout")) weaponFlag = WPN_SCOUT;
    else if (StrEqual(classname, "weapon_sniper_awp"))   weaponFlag = WPN_AWP;
    else return Plugin_Continue;

    if (!(g_iWeaponMask & weaponFlag))
        return Plugin_Continue;

    damage = 10000.0;
    return Plugin_Changed;
}

bool IsValidClient(int client)
{
    return (client > 0 && client <= MaxClients && IsClientInGame(client));
}
