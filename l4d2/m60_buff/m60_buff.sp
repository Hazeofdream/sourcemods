#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdkhooks>

public Plugin myinfo =
{
    name = "M60 Buffs",
    author = "Haze_of_dream",
    description = "Makes the M60 deal extra damage to Tanks.",
    version = "1.0"
};

ConVar g_hDamageMultiplier;

public void OnPluginStart()
{
    g_hDamageMultiplier = CreateConVar(
        "sm_m60_tank_damage_multiplier",
        "2.0",
        "Damage multiplier applied when an M60 hits a Tank.",
        FCVAR_NOTIFY,
        true, 0.0
    );

    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i))
        {
            SDKHook(i, SDKHook_OnTakeDamage, OnTakeDamage);
        }
    }
}

public void OnClientPutInServer(int client)
{
    SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
}

public Action OnTakeDamage(
    int victim,
    int &attacker,
    int &inflictor,
    float &damage,
    int &damagetype
)
{
    if (!IsValidTank(victim))
    {
        return Plugin_Continue;
    }

    if (!IsValidSurvivor(attacker))
    {
        return Plugin_Continue;
    }

    char weapon[64];
    GetClientWeapon(attacker, weapon, sizeof(weapon));

    if (!StrEqual(weapon, "weapon_rifle_m60"))
    {
        return Plugin_Continue;
    }

    damage *= g_hDamageMultiplier.FloatValue;
    return Plugin_Changed;
}

bool IsValidSurvivor(int client)
{
    return (
        client > 0 &&
        client <= MaxClients &&
        IsClientInGame(client) &&
        GetClientTeam(client) == 2
    );
}

bool IsValidTank(int client)
{
    if (
        client <= 0 ||
        client > MaxClients ||
        !IsClientInGame(client) ||
        GetClientTeam(client) != 3
    )
    {
        return false;
    }

    return GetEntProp(client, Prop_Send, "m_zombieClass") == 8;
}