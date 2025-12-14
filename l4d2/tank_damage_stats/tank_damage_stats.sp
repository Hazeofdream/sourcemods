#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

public Plugin myinfo =
{
    name        = "Tank Damage Stats",
    author      = "Haze_of_dream",
    description = "Tracks per-player damage dealt to each Tank and prints stats on Tank death",
    version     = "1.2",
    url         = ""
};

// tankEnt -> damage array [client]
ArrayList g_TankList;
int g_TankDamage[MAXPLAYERS + 1][MAXPLAYERS + 1];

public void OnPluginStart()
{
    g_TankList = new ArrayList();

    HookEvent("player_hurt", Event_PlayerHurt, EventHookMode_Post);
    HookEvent("entity_killed", Event_EntityKilled, EventHookMode_Post);
}

public void Event_PlayerHurt(Event event, const char[] name, bool dontBroadcast)
{
    int victim   = GetClientOfUserId(event.GetInt("userid"));
    int attacker = GetClientOfUserId(event.GetInt("attacker"));
    int damage   = event.GetInt("dmg_health");

    if (damage <= 0)
        return;

    if (!IsValidClient(victim) || !IsValidClient(attacker))
        return;

    if (!IsTank(victim))
        return;

    if (GetClientTeam(attacker) != 2)
        return;

    int tankEnt = victim;

    if (!IsTrackingTank(tankEnt))
    {
        StartTrackingTank(tankEnt);
    }

    g_TankDamage[tankEnt][attacker] += damage;
}

public void Event_EntityKilled(Event event, const char[] name, bool dontBroadcast)
{
    int ent = event.GetInt("entindex_killed");

    // Must be a client entity
    if (ent <= 0 || ent > MaxClients)
        return;

    if (!IsClientInGame(ent))
        return;

    if (!IsTank(ent))
        return;

    int tankEnt = ent;

    if (!IsTrackingTank(tankEnt))
        return;

    PrintTankStats(tankEnt);
    StopTrackingTank(tankEnt);
}

// =======================
// Tank tracking helpers
// =======================

void StartTrackingTank(int tankEnt)
{
    g_TankList.Push(tankEnt);

    for (int i = 1; i <= MaxClients; i++)
    {
        g_TankDamage[tankEnt][i] = 0;
    }
}

void StopTrackingTank(int tankEnt)
{
    int index = g_TankList.FindValue(tankEnt);
    if (index != -1)
    {
        g_TankList.Erase(index);
    }

    for (int i = 1; i <= MaxClients; i++)
    {
        g_TankDamage[tankEnt][i] = 0;
    }
}

bool IsTrackingTank(int tankEnt)
{
    return g_TankList.FindValue(tankEnt) != -1;
}

bool IsTank(int client)
{
    if (GetClientTeam(client) != 3)
        return false;

    int class = GetEntProp(client, Prop_Send, "m_zombieClass");
    return class == 8; // Tank
}

// =======================
// Output
// =======================

void PrintTankStats(int tankEnt)
{
    PrintToChatAll("\x05[ Tank Damage Stats ]");

    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsValidClient(i))
            continue;

        if (GetClientTeam(i) != 2)
            continue;

        PrintToChatAll(
            "\x04%N\x01 dealt %d",
            i,
            g_TankDamage[tankEnt][i]
        );
    }
}

// =======================
// Utils
// =======================

bool IsValidClient(int client)
{
    return client > 0 && client <= MaxClients && IsClientInGame(client);
}
