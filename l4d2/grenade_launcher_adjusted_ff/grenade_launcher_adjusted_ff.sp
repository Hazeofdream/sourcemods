#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdkhooks>
#include <sdktools>

ConVar g_hEnable;
ConVar g_hSelfScale;

public Plugin myinfo =
{
    name        = "Grenade Launcher Adjusted FF",
    author      = "Haze_of_dream",
    description = "Makes Grenade Launcher FF handling easier to control.",
    version     = "1.0",
    url         = ""
};

public void OnPluginStart()
{
    g_hEnable = CreateConVar(
        "gl_adjff_enable",
        "1",
        "Enable Grenade Launcher Adjusted FF plugin",
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

    AutoExecConfig(true, "grenade_launcher_adjusted_ff");

    HookEvent("player_spawn", Event_PlayerSpawn, EventHookMode_Post);
}

public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));

    if (client > 0 && IsClientInGame(client))
    {
        SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
    }
}

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
		float finalDamage = damage * g_hSelfScale.FloatValue;

		int health = GetClientHealth(victim);
		bool incapacitated = GetEntProp(victim, Prop_Send, "m_isIncapacitated") != 0;

		// If this damage would kill or incap, preserve survivor ownership
		if (!incapacitated && finalDamage >= float(health))
		{
			damage = finalDamage;
			return Plugin_Changed;
		}

		// Normal self-damage scaling
		damage = finalDamage;
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

bool IsSurvivor(int client)
{
    return GetClientTeam(client) == 2;
}

bool IsValidClient(int client)
{
    return client > 0 && client <= MaxClients && IsClientInGame(client);
}
