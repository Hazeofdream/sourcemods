#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

public Plugin myinfo =
{
    name        = "Tank Rock No IFrames",
    author      = "Haze_of_dream",
    description = "Removes invulnerability frames from Tank rocks so they are damageable immediately",
    version     = "1.1"
};

public void OnEntityCreated(int entity, const char[] classname)
{
    if (!StrEqual(classname, "tank_rock"))
        return;

    // One-frame delay to ensure props exist
    CreateTimer(0.0, MakeRockDamageable, EntIndexToEntRef(entity),
        TIMER_FLAG_NO_MAPCHANGE);
}

public Action MakeRockDamageable(Handle timer, int entRef)
{
    int entity = EntRefToEntIndex(entRef);
    if (entity == INVALID_ENT_REFERENCE || !IsValidEntity(entity))
        return Plugin_Stop;

    // Force damageable immediately
    SetEntProp(entity, Prop_Data, "m_takedamage", 2); // DAMAGE_YES

    // Safety: ensure rock has health
    if (GetEntProp(entity, Prop_Data, "m_iHealth") <= 0)
    {
        SetEntProp(entity, Prop_Data, "m_iHealth", 1000);
    }

    return Plugin_Stop;
}