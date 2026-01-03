#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

// =======================
// Plugin Info
// =======================

public Plugin myinfo =
{
    name        = "Tank Damage Stats",
    author      = "Haze_of_dream",
    description = "Tracks and prints per-player damage dealt to each Tank",
    version     = "1.2"
};

// =======================
// Constants / Limits
// =======================

#define MAX_TRACKED_TANKS 8

// =======================
// Data
// =======================

int  g_TankEnt[MAX_TRACKED_TANKS];
int  g_TankSpawnHP[MAX_TRACKED_TANKS];
int  g_TankCount;

int  g_TankDamage[MAX_TRACKED_TANKS][MAXPLAYERS + 1];
int g_SortTankId = -1;
char g_PlayerName[MAXPLAYERS + 1][MAX_NAME_LENGTH];

ConVar g_hShowPercent;

// =======================
// Plugin Init
// =======================

public void OnPluginStart()
{
    g_hShowPercent = CreateConVar(
        "tank_damage_stats_show_percent",
        "1",
        "Show percentage contribution per player",
        FCVAR_NOTIFY,
        true, 0.0,
        true, 1.0
    );

    AutoExecConfig(true, "tank_damage_stats");

    HookEvent("player_hurt",   Event_PlayerHurt,   EventHookMode_Post);
    HookEvent("infected_hurt", Event_InfectedHurt, EventHookMode_Post);
    HookEvent("entity_killed", Event_EntityKilled, EventHookMode_Post);
}

// =======================
// Tank Tracking
// =======================

bool IsTank(int client)
{
    return client > 0
        && client <= MaxClients
        && IsClientInGame(client)
        && GetClientTeam(client) == 3
        && GetEntProp(client, Prop_Send, "m_zombieClass") == 8;
}

int FindOrCreateTank(int ent)
{
    for (int i = 0; i < g_TankCount; i++)
    {
        if (g_TankEnt[i] == ent)
            return i;
    }

    if (g_TankCount >= MAX_TRACKED_TANKS)
        return -1;

    int id = g_TankCount;

    g_TankEnt[id]      = ent;
    g_TankSpawnHP[id]  = GetEntProp(ent, Prop_Data, "m_iHealth");

    for (int i = 1; i <= MaxClients; i++)
        g_TankDamage[id][i] = 0;

    g_TankCount++;
    return id;
}

// =======================
// Damage Attribution
// =======================

void ApplyTankDamage(int tankEnt, int attacker, int dmg)
{
    if (dmg <= 0)
        return;

    if (attacker <= 0 || attacker > MaxClients)
        return;

    if (!IsClientInGame(attacker))
        return;

    if (GetClientTeam(attacker) != 2)
        return;

    int id = FindOrCreateTank(tankEnt);
    if (id == -1)
        return;

    GetClientName(attacker, g_PlayerName[attacker], sizeof(g_PlayerName[]));
    g_TankDamage[id][attacker] += dmg;
}

// =======================
// Event Hooks
// =======================

public void Event_PlayerHurt(Event event, const char[] name, bool dontBroadcast)
{
    int victim   = GetClientOfUserId(event.GetInt("userid"));
    int attacker = GetClientOfUserId(event.GetInt("attacker"));

    if (!IsTank(victim))
        return;

    ApplyTankDamage(victim, attacker, event.GetInt("dmg_health"));
}

public void Event_InfectedHurt(Event event, const char[] name, bool dontBroadcast)
{
    int victim = event.GetInt("entityid");
    if (!IsTank(victim))
        return;

    int inflictor = event.GetInt("attackerentid");
    if (!IsValidEntity(inflictor))
        return;

    int owner = GetEntPropEnt(inflictor, Prop_Data, "m_hOwnerEntity");

    if (owner <= 0 || owner > MaxClients || !IsClientInGame(owner))
        return;

    ApplyTankDamage(victim, owner, event.GetInt("amount"));
}

public void Event_EntityKilled(Event event, const char[] name, bool dontBroadcast)
{
    int ent = event.GetInt("entindex_killed");

    for (int id = 0; id < g_TankCount; id++)
    {
        if (g_TankEnt[id] == ent)
        {
            PrintTankStats(id);
            RemoveTank(id);
            return;
        }
    }
}

// =======================
// Tank Removal
// =======================

void RemoveTank(int id)
{
    for (int i = id; i < g_TankCount - 1; i++)
    {
        g_TankEnt[i]     = g_TankEnt[i + 1];
        g_TankSpawnHP[i] = g_TankSpawnHP[i + 1];

        for (int c = 1; c <= MaxClients; c++)
            g_TankDamage[i][c] = g_TankDamage[i + 1][c];
    }

    g_TankCount--;
}

// =======================
// Output
// =======================

void PrintTankStats(int id)
{
    PrintToChatAll("\x05---= [ Tank Damage Stats ] =---");

    ArrayList players = new ArrayList();
    int totalDamage = 0;

    // Collect all survivors (including 0-damage)
    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientInGame(i))
            continue;

        if (GetClientTeam(i) != 2)
            continue;

        players.Push(i);
        totalDamage += g_TankDamage[id][i];
    }

    // Sort by damage: highest -> lowest
    g_SortTankId = id;
    players.SortCustom(SortByDamageDesc);
    g_SortTankId = -1;

    bool showPct = g_hShowPercent.BoolValue;

    for (int i = 0; i < players.Length; i++)
    {
        int client = players.Get(i);
        int dmg    = g_TankDamage[id][client];

        char dmgStr[32];
        FormatNumber(dmgStr, sizeof(dmgStr), dmg);

        if (showPct && totalDamage > 0)
        {
            int pct = RoundToNearest(float(dmg) / float(totalDamage) * 100.0);
            PrintToChatAll(
                "\x04%s\x01 did %s (%d%%)",
                g_PlayerName[client],
                dmgStr,
                pct
            );
        }
        else
        {
            PrintToChatAll(
                "\x04%s\x01 did %s",
                g_PlayerName[client],
                dmgStr
            );
        }
    }

    char hpStr[32];
    FormatNumber(hpStr, sizeof(hpStr), g_TankSpawnHP[id]);

    PrintToChatAll(
        "\x01out of %s health total",
        hpStr
    );

    delete players;
}

// =======================
// Sorting
// =======================

public int SortByDamageDesc(int a, int b, ArrayList list, Handle hndl)
{
    int dmgA = g_TankDamage[g_SortTankId][a];
    int dmgB = g_TankDamage[g_SortTankId][b];
    return dmgB - dmgA;
}

// =======================
// Utils
// =======================

void FormatNumber(char[] buffer, int maxlen, int value)
{
    char temp[32];
    IntToString(value, temp, sizeof(temp));

    int len = strlen(temp);
    int commas = (len - 1) / 3;
    int outLen = len + commas;

    if (outLen >= maxlen)
        outLen = maxlen - 1;

    buffer[outLen] = '\0';

    int src = len - 1;
    int dst = outLen - 1;
    int count = 0;

    while (src >= 0)
    {
        buffer[dst--] = temp[src--];
        if (++count == 3 && src >= 0)
        {
            buffer[dst--] = ',';
            count = 0;
        }
    }
}