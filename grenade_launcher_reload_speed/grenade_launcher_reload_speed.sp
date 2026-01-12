#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

public Plugin myinfo =
{
    name        = "Grenade Launcher Reload Speed",
    author      = "Haze_of_dream",
    description = "Reduces grenade launcher reload time",
    version     = "1.2"
};

ConVar g_hReloadMultiplier;

public void OnPluginStart()
{
    g_hReloadMultiplier = CreateConVar(
        "grenade_launcher_reload_multiplier",
        "0.7",
        "Reload time multiplier for grenade launcher (0.5 = 50% faster)",
        FCVAR_NOTIFY,
        true, 0.1,
        true, 1.0
    );

    AutoExecConfig(true, "grenade_launcher_reload_speed");

    HookEvent("weapon_reload", Event_WeaponReload, EventHookMode_Post);
}

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

bool IsValidClient(int client)
{
    return client > 0 && client <= MaxClients && IsClientInGame(client);
}