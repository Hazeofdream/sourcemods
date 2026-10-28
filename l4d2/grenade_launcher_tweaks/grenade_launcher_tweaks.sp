#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdkhooks>
#include <sdktools>

public Plugin myinfo =
{
    name        = "Grenade Launcher Tweaks",
    author      = "Haze_of_dream",
    description = "Grenade Launcher friendly fire handling and faster reloads.",
    version     = "2.0",
    url         = ""
};

// Friendly fire
ConVar g_hEnable;
ConVar g_hSelfScale;

// Reload speed
ConVar g_hReloadMultiplier;

public void OnPluginStart()
{
    g_hEnable = CreateConVar(
        "gl_adjff_enable",
        "1",
        "Enable Grenade Launcher adjusted FF (teammates take no grenade launcher damage)",
        FCVAR_NOTIFY,
        true, 0.0,
        true, 1.0
    );

    g_hSelfScale = CreateConVar(
        "gl_adjff_self_scale",
        "1.0",
        "Scale for grenade launcher self-damage",
        FCVAR_NOTIFY,
        true, 0.0,
        true, 10.0
    );

    g_hReloadMultiplier = CreateConVar(
        "grenade_launcher_reload_multiplier",
        "0.7",
        "Reload time multiplier for grenade launcher (0.5 = 50% faster, 1.0 = default)",
        FCVAR_NOTIFY,
        true, 0.1,
        true, 1.0
    );

    AutoExecConfig(true, "grenade_launcher_tweaks");

    HookEvent("weapon_reload", Event_WeaponReload, EventHookMode_Post);

    // Late load
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i))
            OnClientPutInServer(i);
    }
}

public void OnClientPutInServer(int client)
{
    SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
}

// =====================
// Friendly fire
// =====================

public Action OnTakeDamage(
    int victim,
    int &attacker,
    int &inflictor,
    float &damage,
    int &damagetype
)
{
    if (!g_hEnable.BoolValue)
        return Plugin_Continue;

    if (!IsValidClient(victim) || !IsValidClient(attacker))
        return Plugin_Continue;

    if (!IsSurvivor(victim) || !IsSurvivor(attacker))
        return Plugin_Continue;

    if (!IsGrenadeLauncherDamage(inflictor))
        return Plugin_Continue;

    // --- Self-damage ---
    if (victim == attacker)
    {
        damage *= g_hSelfScale.FloatValue;
        return Plugin_Changed;
    }

    // --- Teammate damage ---
    attacker = 0;
    inflictor = 0;
    damage = 0.0;
    return Plugin_Changed;
}

bool IsGrenadeLauncherDamage(int inflictor)
{
    if (!IsValidEntity(inflictor))
        return false;

    char classname[64];
    GetEntityClassname(inflictor, classname, sizeof(classname));

    // grenade_launcher_projectile is the explosive entity
    return StrEqual(classname, "grenade_launcher_projectile");
}

// =====================
// Reload speed
// =====================

public void Event_WeaponReload(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!IsValidClient(client))
        return;

    int weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
    if (weapon <= 0)
        return;

    char classname[64];
    GetEntityClassname(weapon, classname, sizeof(classname));

    if (!StrEqual(classname, "weapon_grenade_launcher"))
        return;

    float mult = g_hReloadMultiplier.FloatValue;
    if (mult >= 1.0)
        return;

    float now = GetGameTime();

    // ---- Weapon fire gate ----
    float wNext = GetEntPropFloat(weapon, Prop_Send, "m_flNextPrimaryAttack");
    float wDelta = wNext - now;

    if (wDelta > 0.0)
    {
        SetEntPropFloat(
            weapon,
            Prop_Send,
            "m_flNextPrimaryAttack",
            now + (wDelta * mult)
        );
    }

    // ---- Player fire gate ----
    float pNext = GetEntPropFloat(client, Prop_Send, "m_flNextAttack");
    float pDelta = pNext - now;

    if (pDelta > 0.0)
    {
        SetEntPropFloat(
            client,
            Prop_Send,
            "m_flNextAttack",
            now + (pDelta * mult)
        );
    }

    // Speed up animation for visual consistency
    SetEntPropFloat(
        weapon,
        Prop_Send,
        "m_flPlaybackRate",
        1.0 / mult
    );
}

// =====================
// Utilities
// =====================

bool IsSurvivor(int client)
{
    return GetClientTeam(client) == 2;
}

bool IsValidClient(int client)
{
    return client > 0 && client <= MaxClients && IsClientInGame(client);
}
