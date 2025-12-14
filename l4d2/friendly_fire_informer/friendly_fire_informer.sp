#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#define TEAM_SURVIVOR 2

// Damage aggregation per frame
int g_FrameDamage[MAXPLAYERS + 1][MAXPLAYERS + 1];
bool g_FrameScheduled = false;

public Plugin myinfo =
{
    name        = "Friendly Fire Informer",
    author      = "Haze_of_dream",
    description = "Reports friendly fire and incap incidents.",
    version     = "1.2"
};

public void OnPluginStart()
{
    HookEvent("player_hurt", Event_PlayerHurt, EventHookMode_Post);
}

public Action Event_PlayerHurt(Event event, const char[] name, bool dontBroadcast)
{
    int victim   = GetClientOfUserId(event.GetInt("userid"));
    int attacker = GetClientOfUserId(event.GetInt("attacker"));

    if (victim <= 0 || attacker <= 0)
    {
        return Plugin_Continue;
    }

    if (victim == attacker)
    {
        return Plugin_Continue;
    }

    if (!IsClientInGame(victim) || !IsClientInGame(attacker))
    {
        return Plugin_Continue;
    }

    if (GetClientTeam(victim) != TEAM_SURVIVOR ||
        GetClientTeam(attacker) != TEAM_SURVIVOR)
    {
        return Plugin_Continue;
    }

    // Ignore damage to incapped players
    if (GetEntProp(victim, Prop_Send, "m_isIncapacitated") == 1)
    {
        return Plugin_Continue;
    }

    int dmg = event.GetInt("dmg_health");
    if (dmg <= 0)
    {
        return Plugin_Continue;
    }

    g_FrameDamage[attacker][victim] += dmg;

    if (!g_FrameScheduled)
    {
        g_FrameScheduled = true;
        RequestFrame(ProcessFrameDamage);
    }

    return Plugin_Continue;
}

public void ProcessFrameDamage(any data)
{
    g_FrameScheduled = false;

    char attackerName[64];
    char victimName[64];

    for (int attacker = 1; attacker <= MaxClients; attacker++)
    {
        if (!IsClientInGame(attacker))
        {
            continue;
        }

        for (int victim = 1; victim <= MaxClients; victim++)
        {
            int totalDamage = g_FrameDamage[attacker][victim];
            if (totalDamage <= 0)
            {
                continue;
            }

            g_FrameDamage[attacker][victim] = 0;

            if (!IsClientInGame(victim))
            {
                continue;
            }

            GetClientName(attacker, attackerName, sizeof(attackerName));
            GetClientName(victim, victimName, sizeof(victimName));

            int health = GetClientHealth(victim);

            // Check incap state AFTER damage
            bool incapped = (GetEntProp(victim, Prop_Send, "m_isIncapacitated") == 1);

            if (incapped)
            {
                // Health before damage is what actually mattered
                int hpBefore = health + totalDamage;

                PrintToChatAll(
                    "\x03%s \x01downed \x04%s \x01for \x05%d\x01 damage (\x05%d\x01 HP total)",
                    attackerName,
                    victimName,
                    totalDamage,
                    hpBefore
                );
            }
            else
            {
                PrintToChatAll(
                    "\x03%s \x01dealt \x05%d\x01 damage to \x04%s\x01, Total hp: \x05%d\x01/100",
                    attackerName,
                    totalDamage,
                    victimName,
                    health
                );
            }
        }
    }
}
