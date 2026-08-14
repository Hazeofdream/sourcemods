#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

public Plugin myinfo =
{
    name        = "Difficulty Enforcer",
    author      = "Haze_of_dream",
    description = "Prevents players from modifying server difficulty",
    version     = "1.1"
};

public void OnPluginStart()
{
    AddCommandListener(VoteListener, "callvote");
}

public Action VoteListener(int client, const char[] command, int argc)
{
    if (argc < 1)
        return Plugin_Continue;

    char issue[64];
    GetCmdArg(1, issue, sizeof(issue));

    if (StrEqual(issue, "ChangeDifficulty", false))
    {
        PrintToChatAll(
            "\x05[Hard Mode]\x01 %N, Difficulty votes are disabled on this server.",
            client
        );

        return Plugin_Handled;
    }

    return Plugin_Continue;
}