#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

ConVar g_hPipeDuration;

public Plugin myinfo =
{
    name        = "Pipebomb Modifier",
    author      = "Haze_of_dream",
    description = "Allows changing pipe bomb fuse duration via cvar",
    version     = "1.0",
    url         = ""
};

public void OnPluginStart()
{
    g_hPipeDuration = CreateConVar(
        "pipebomb_duration",
        "12.0",
        "How long (in seconds) pipe bombs last before exploding",
        FCVAR_NOTIFY,
        true, 0.1,
        true, 30.0
    );

    AutoExecConfig(true, "pipebomb_modifier");
}

public void OnEntityCreated(int entity, const char[] classname)
{
    if (!StrEqual(classname, "pipe_bomb_projectile"))
        return;

    // Delay one frame so netprops exist
    CreateTimer(0.0, Timer_AdjustPipe, EntIndexToEntRef(entity));
}

public Action Timer_AdjustPipe(Handle timer, int ref)
{
    int entity = EntRefToEntIndex(ref);
    if (entity == INVALID_ENT_REFERENCE)
        return Plugin_Stop;

    float duration = g_hPipeDuration.FloatValue;
    float gameTime = GetGameTime();

    SetEntPropFloat(entity, Prop_Send, "m_flDetonateTime", gameTime + duration);

    return Plugin_Stop;
}
