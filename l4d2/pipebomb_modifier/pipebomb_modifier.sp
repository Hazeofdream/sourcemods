#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

public Plugin myinfo =
{
    name        = "Pipebomb Modifier",
    author      = "Haze_of_dream",
    description = "Correctly modifies pipe bomb fuse time and beep scaling",
    version     = "1.1"
};

ConVar g_hFuseTime;

#define VANILLA_FUSE 6.0

public void OnPluginStart()
{
    g_hFuseTime = CreateConVar(
        "pipebomb_fuse_time",
        "12.0",
        "Pipe bomb fuse time in seconds",
        FCVAR_NOTIFY,
        true, 1.0,
        true, 60.0
    );

    AutoExecConfig(true, "pipebomb_modifier");
}

public void OnEntityCreated(int entity, const char[] classname)
{
    if (!StrEqual(classname, "pipe_bomb_projectile"))
        return;

    // One-frame delay so netprops exist
    CreateTimer(0.0, AdjustPipeBombFuse, EntIndexToEntRef(entity));
}

public Action AdjustPipeBombFuse(Handle timer, any ref)
{
    int ent = EntRefToEntIndex(ref);
    if (ent == INVALID_ENT_REFERENCE)
        return Plugin_Stop;

    float fuse = g_hFuseTime.FloatValue;
    float now  = GetGameTime();

    // Set new detonation time
    SetEntPropFloat(ent, Prop_Send, "m_flDetonateTime", now + fuse);

    // Scale beep think interval properly
    float scale = fuse / VANILLA_FUSE;
    float nextBeep = now + (0.45 * scale);

    // This prop DOES exist and controls beep pacing
    SetEntPropFloat(ent, Prop_Send, "m_flNextBeepTime", nextBeep);

    return Plugin_Stop;
}