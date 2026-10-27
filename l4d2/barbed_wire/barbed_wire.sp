/**
 * [L4D2] Barbed Wire
 * Build/dismantle with the CSS knife. Secondary fire builds while held; zoom dismantles;
 * reload rotates placement. Survivors, infected players and common infected are damaged/slowed.
 * Every wire has an independent damage timer per target, so overlapping wires stack damage.
 * Commands: sm_barbedwire (give tool), sm_clearwire (ADMFLAG_SLAY removes all wires).
 * Requires SourceMod 1.10+, SDKTools, SDKHooks.
 */
#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#define WIRE_MODEL "models/props_fortifications/barricade_razorwire001_128_reference.mdl"
#define WIRE_NAME "sm_barbedwire"
#define GHOST_NAME "sm_barbedwire_ghost"
#define SND_DAMAGE "physics/metal/metal_chainlink_impact_soft2.wav"
#define SND_BUILD "physics/metal/metal_chainlink_impact_soft3.wav"
#define SND_REMOVE "physics/metal/metal_grenade_impact_hard2.wav"
#define TEAM_SURVIVOR 2
#define TEAM_INFECTED 3
#define ZC_TANK 8
#define MAX_WIRES 128

enum struct WireData
{
    int ref;
    int slot;
    int ownerUserId;
    int builderUserId;
    float yaw;
    float buildStart;
    float buildEnd;
    bool done;
    int alpha;
    int lastPct;
    float pos[3];
    float mins[3];
    float maxs[3];
}

ConVar g_cvEnable, g_cvMaxDist, g_cvDamage, g_cvInterval, g_cvSlow, g_cvMaxWires, g_cvTankImmune;
ConVar g_cvCooldown, g_cvBuildTime, g_cvBlockMelee, g_cvGlow;
ArrayList g_Wires;

int g_GhostRef[MAXPLAYERS + 1] = {-1, ...};
int g_BuildRef[MAXPLAYERS + 1] = {-1, ...};
float g_BuildPos[MAXPLAYERS + 1][3];
int g_GhostState[MAXPLAYERS + 1];
int g_RotState[MAXPLAYERS + 1];
int g_LastButtons[MAXPLAYERS + 1];
float g_NextAction[MAXPLAYERS + 1];
int g_GhostOwner[2049];
int g_TargetRef[2049];
bool g_Slowed[2049];
bool g_AnySlowed;
float g_LastPos[2049][3];
bool g_HasLastPos[2049];
float g_SlotNextDmg[MAX_WIRES][2049];
bool g_SlotUsed[MAX_WIRES];

public Plugin myinfo =
{
    name = "[L4D2] Barbed Wire",
    author = "Haze_of_dream",
    description = "Build and dismantle barbed wire with the CSS knife; wire damages and slows survivors, infected and common infected.",
    version = "1.0",
    url = ""
};

public void OnPluginStart()
{
    if (GetEngineVersion() != Engine_Left4Dead2)
        SetFailState("This plugin only works on Left 4 Dead 2.");

    g_cvEnable = CreateConVar("sm_barbedwire_enable", "1", "Enable the plugin.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_cvMaxDist = CreateConVar("sm_barbedwire_distance", "150.0", "Maximum placement/dismantle distance from eyes.", FCVAR_NOTIFY, true, 16.0, true, 1000.0);
    g_cvDamage = CreateConVar("sm_barbedwire_damage", "10.0", "Damage each wire deals per tick.", FCVAR_NOTIFY, true, 0.0);
    g_cvTankImmune = CreateConVar("sm_barbedwire_tank_immune", "1", "Make tanks immune to barbed wire slowdown", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_cvInterval = CreateConVar("sm_barbedwire_interval", "0.5", "Seconds between damage ticks per wire and target.", FCVAR_NOTIFY, true, 0.05);
    g_cvSlow = CreateConVar("sm_barbedwire_slow", "0.2", "Movement multiplier while touching any wire.", FCVAR_NOTIFY, true, 0.05, true, 1.0);
    g_cvMaxWires = CreateConVar("sm_barbedwire_max", "3", "Maximum wires per player.", FCVAR_NOTIFY, true, 1.0, true, 100.0);
    g_cvCooldown = CreateConVar("sm_barbedwire_cooldown", "0.4", "Seconds between build starts/dismantles.", FCVAR_NOTIFY, true, 0.0);
    g_cvBuildTime = CreateConVar("sm_barbedwire_build_time", "1", "Hold secondary fire this long to build; 0 = instant.", FCVAR_NOTIFY, true, 0.0, true, 60.0);
    g_cvBlockMelee = CreateConVar("sm_barbedwire_block_melee", "1", "Consume secondary fire and zoom for build/dismantle.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_cvGlow = CreateConVar("sm_barbedwire_glow", "1", "Outline the placement hologram.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    AutoExecConfig(true, "barbed_wire");

    RegConsoleCmd("sm_barbedwire", Cmd_GiveKnife, "Give the knife used to build barbed wire.");
    RegAdminCmd("sm_clearwire", Cmd_ClearWires, ADMFLAG_SLAY, "Remove all barbed wire.");
    HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
    HookEvent("round_end", Event_RoundEnd, EventHookMode_PostNoCopy);
    HookEvent("player_death", Event_PlayerDeath);
    g_Wires = new ArrayList(sizeof(WireData));
}

public void OnMapStart()
{
    PrecacheModel(WIRE_MODEL, true);
    PrecacheSound(SND_DAMAGE, true);
    PrecacheSound(SND_BUILD, true);
    PrecacheSound(SND_REMOVE, true);
    PrecacheModel("models/v_models/v_knife_t.mdl", true);
    PrecacheModel("models/w_models/weapons/w_knife_t.mdl", true);
    PrecacheGeneric("scripts/melee/knife.txt", true);
    ResetAll();
}

public void OnMapEnd() { ResetAll(); }

public void OnPluginEnd()
{
    for (int i = 1; i <= MaxClients; i++) RemoveGhost(i);
    ResetAllSlows();
    ClearAllWires();
}

public void OnClientDisconnect(int client)
{
    RemoveGhost(client);
    g_BuildRef[client] = -1;
    g_Slowed[client] = false;
    g_TargetRef[client] = 0;
    g_LastButtons[client] = 0;
    g_NextAction[client] = 0.0;
    g_RotState[client] = 0;
}

void ResetAll()
{
    ResetAllSlows();
    if (g_Wires != null) g_Wires.Clear();
    g_AnySlowed = false;
    for (int s = 0; s < MAX_WIRES; s++) g_SlotUsed[s] = false;
    for (int i = 0; i <= 2048; i++)
    {
        g_GhostOwner[i] = 0;
        g_TargetRef[i] = 0;
        g_Slowed[i] = false;
        g_HasLastPos[i] = false;
    }
    for (int i = 1; i <= MaxClients; i++)
    {
        g_GhostRef[i] = -1;
        g_BuildRef[i] = -1;
        g_GhostState[i] = 0;
    }
}

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
    ClearAllWires();
    ResetAll();
}

public void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
    for (int i = 1; i <= MaxClients; i++) RemoveGhost(i);
    ResetAllSlows();
    ClearAllWires();
}

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client > 0)
    {
        RemoveGhost(client);
        ResetSlow(client);
    }
}

/* Commands */
public Action Cmd_GiveKnife(int client, int args)
{
    if (client == 0)
    {
        ReplyToCommand(client, "[Barbed Wire] This command can only be used in game.");
        return Plugin_Handled;
    }
    if (!IsClientInGame(client) || !IsPlayerAlive(client) || GetClientTeam(client) != TEAM_SURVIVOR)
    {
        ReplyToCommand(client, "[Barbed Wire] You must be an alive survivor.");
        return Plugin_Handled;
    }

    // L4D2 melee weapons use weapon_melee. "give knife" asks GiveNamedItem for
    // the nonexistent weapon_knife classname and causes the NULL Ent error.
    int knife = CreateEntityByName("weapon_melee");
    if (knife == -1 || !IsValidEntity(knife))
    {
        PrintToChat(client, "[Barbed Wire] Failed to create weapon_melee.");
        return Plugin_Handled;
    }
    DispatchKeyValue(knife, "melee_script_name", "knife");
    DispatchSpawn(knife);
    if (!IsValidEntity(knife))
    {
        PrintToChat(client, "[Barbed Wire] Failed to spawn the knife melee weapon.");
        return Plugin_Handled;
    }

    char scriptName[32];
    GetEntPropString(knife, Prop_Data, "m_strMapSetScriptName", scriptName, sizeof(scriptName));
    if (!StrEqual(scriptName, "knife", false))
    {
        AcceptEntityInput(knife, "Kill");
        PrintToChat(client, "[Barbed Wire] The knife melee script is unavailable on this server/map.");
        return Plugin_Handled;
    }

    float origin[3];
    GetClientAbsOrigin(client, origin);
    origin[2] += 8.0;
    TeleportEntity(knife, origin, NULL_VECTOR, NULL_VECTOR);

    // Do not remove the existing secondary until the replacement is validated.
    int oldWeapon = GetPlayerWeaponSlot(client, 1);
    if (oldWeapon > MaxClients && IsValidEntity(oldWeapon))
    {
        RemovePlayerItem(client, oldWeapon);
        AcceptEntityInput(oldWeapon, "Kill");
    }
    EquipPlayerWeapon(client, knife);
    FakeClientCommand(client, "use weapon_melee");
    PrintToChat(client, "\x04[Barbed Wire]\x01 Knife equipped. \x05Hold Secondary\x01 = build, \x05Zoom\x01 = dismantle.");
    return Plugin_Handled;
}

public Action Cmd_ClearWires(int client, int args)
{
    ClearAllWires();
    ReplyToCommand(client, "[Barbed Wire] All barbed wire removed.");
    return Plugin_Handled;
}

void ClearAllWires()
{
    if (g_Wires == null) return;
    for (int i = g_Wires.Length - 1; i >= 0; i--)
    {
        WireData w;
        g_Wires.GetArray(i, w);
        int ent = EntRefToEntIndex(w.ref);
        if (ent != INVALID_ENT_REFERENCE) AcceptEntityInput(ent, "Kill");
    }
    g_Wires.Clear();
    for (int s = 0; s < MAX_WIRES; s++) g_SlotUsed[s] = false;
    for (int i = 1; i <= MaxClients; i++) g_BuildRef[i] = -1;
}

int AllocSlot()
{
    for (int s = 0; s < MAX_WIRES; s++)
    {
        if (!g_SlotUsed[s])
        {
            g_SlotUsed[s] = true;
            for (int e = 0; e <= 2048; e++) g_SlotNextDmg[s][e] = 0.0;
            return s;
        }
    }
    return -1;
}

void EraseWire(int index)
{
    WireData w;
    g_Wires.GetArray(index, w);
    if (w.slot >= 0 && w.slot < MAX_WIRES) g_SlotUsed[w.slot] = false;
    g_Wires.Erase(index);
}

int FindWireByRef(int ref)
{
    for (int i = 0; i < g_Wires.Length; i++)
    {
        WireData w;
        g_Wires.GetArray(i, w);
        if (w.ref == ref) return i;
    }
    return -1;
}

int CountOwned(int userid)
{
    int count = 0;
    for (int i = 0; i < g_Wires.Length; i++)
    {
        WireData w;
        g_Wires.GetArray(i, w);
        if (w.ownerUserId == userid && EntRefToEntIndex(w.ref) != INVALID_ENT_REFERENCE) count++;
    }
    return count;
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
    int prev = g_LastButtons[client];
    g_LastButtons[client] = buttons;
    int pressed = buttons & ~prev;
    int held = buttons;

    if (!g_cvEnable.BoolValue || !CanUseTool(client))
    {
        RemoveGhost(client);
        CancelBuild(client, false);
        return Plugin_Continue;
    }

    bool building = IsBuilding(client);
    if (!building && (pressed & IN_RELOAD))
    {
        g_RotState[client] = (g_RotState[client] == 0) ? 1 : 0;
    }

    float eye[3], fwd[3], pos[3], ang[3], dist;
    ComputePlacement(client, eye, fwd, dist, pos, ang);
    int userid = GetClientUserId(client);
    float now = GetGameTime();

    if (building)
    {
        RemoveGhost(client);
        if (!(held & IN_ATTACK))
            CancelBuild(client, true);
        else if (GetVectorDistance(eye, g_BuildPos[client]) > g_cvMaxDist.FloatValue + 64.0)
            CancelBuild(client, true);
    }
    else
    {
        bool atLimit = (CountOwned(userid) >= g_cvMaxWires.IntValue);
        UpdateGhost(client, pos, ang, !atLimit);
        if (now >= g_NextAction[client])
        {
            if (pressed & IN_ATTACK)
            {
                g_NextAction[client] = now + g_cvCooldown.FloatValue;
                if (atLimit)
                    PrintHintText(client, "Barbed wire limit reached (%d). Dismantle one first.", g_cvMaxWires.IntValue);
                else
                    StartBuild(client, userid, pos, ang);
            }
            else if (pressed & IN_ZOOM)
            {
                g_NextAction[client] = now + g_cvCooldown.FloatValue;
                if (!RemoveWireAimedAt(eye, fwd, dist)) PrintHintText(client, "No barbed wire in range.");
            }
        }
    }

    if (g_cvBlockMelee.BoolValue)
    {
        buttons &= ~(IN_ATTACK | IN_ZOOM);
        return Plugin_Changed;
    }
    return Plugin_Continue;
}

bool CanUseTool(int client)
{
    if (!IsClientInGame(client) || IsFakeClient(client) || !IsPlayerAlive(client)) return false;
    if (GetClientTeam(client) != TEAM_SURVIVOR) return false;
    if (GetEntProp(client, Prop_Send, "m_isIncapacitated") != 0) return false;
    return IsHoldingKnife(client);
}

bool IsHoldingKnife(int client)
{
    int wep = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
    if (wep <= MaxClients || !IsValidEntity(wep)) return false;
    char buf[64];
    GetEdictClassname(wep, buf, sizeof(buf));
    if (!StrEqual(buf, "weapon_melee")) return false;
    GetEntPropString(wep, Prop_Data, "m_strMapSetScriptName", buf, sizeof(buf));
    return StrEqual(buf, "knife", false);
}

void ComputePlacement(int client, float eye[3], float fwd[3], float &dist, float pos[3], float ang[3])
{
    float eyeAng[3], end[3];
    GetClientEyePosition(client, eye);
    GetClientEyeAngles(client, eyeAng);
    GetAngleVectors(eyeAng, fwd, NULL_VECTOR, NULL_VECTOR);
    float maxDist = g_cvMaxDist.FloatValue;
    for (int i = 0; i < 3; i++) end[i] = eye[i] + fwd[i] * maxDist;

    TR_TraceRayFilter(eye, end, MASK_SOLID, RayType_EndPoint, TraceFilter, client);
    dist = maxDist;
    if (TR_DidHit())
    {
        float normal[3];
        TR_GetEndPosition(pos);
        TR_GetPlaneNormal(INVALID_HANDLE, normal);
        dist = GetVectorDistance(eye, pos);
        for (int i = 0; i < 3; i++) pos[i] += normal[i] * 2.0;
    }
    else
    {
        for (int i = 0; i < 3; i++) pos[i] = end[i];
    }

    float from[3], to[3], ground[3];
    for (int i = 0; i < 3; i++) { from[i] = pos[i]; to[i] = pos[i]; }
    from[2] += 8.0;
    to[2] -= 64.0;
    TR_TraceRayFilter(from, to, MASK_SOLID, RayType_EndPoint, TraceFilter, client);
    if (TR_DidHit() && !TR_StartSolid())
    {
        TR_GetEndPosition(ground);
        pos[2] = ground[2];
    }

    ang[0] = 0.0;
    ang[1] = eyeAng[1] + (g_RotState[client] == 1 ? 90.0 : 0.0);
    ang[2] = 0.0;
}

public bool TraceFilter(int entity, int contentsMask, any data)
{
    if (entity >= 1 && entity <= MaxClients) return false;
    if (entity > MaxClients && IsValidEntity(entity))
    {
        char name[48];
        GetEntPropString(entity, Prop_Data, "m_iName", name, sizeof(name));
        if (strncmp(name, WIRE_NAME, strlen(WIRE_NAME)) == 0) return false;
    }
    return true;
}

/* Hologram preview */
void UpdateGhost(int client, const float pos[3], const float ang[3], bool valid)
{
    int ghost = EntRefToEntIndex(g_GhostRef[client]);
    if (ghost == INVALID_ENT_REFERENCE)
    {
        ghost = CreateGhost(client);
        if (ghost == -1) return;
        g_GhostRef[client] = EntIndexToEntRef(ghost);
        g_GhostState[client] = 0;
    }
    int state = valid ? 1 : 2;
    if (g_GhostState[client] != state)
    {
        g_GhostState[client] = state;
        if (valid) ColorGhost(ghost, 0, 255, 160);
        else ColorGhost(ghost, 255, 40, 40);
    }
    TeleportEntity(ghost, pos, ang, NULL_VECTOR);
}

int CreateGhost(int client)
{
    int ent = CreateEntityByName("prop_dynamic_override");
    if (ent == -1) return -1;
    SetEntityModel(ent, WIRE_MODEL);
    DispatchKeyValue(ent, "targetname", GHOST_NAME);
    DispatchKeyValue(ent, "solid", "0");
    DispatchSpawn(ent);
    SetEntityRenderMode(ent, RENDER_TRANSCOLOR);
    g_GhostOwner[ent] = client;
    SDKHook(ent, SDKHook_SetTransmit, Hook_GhostTransmit);
    return ent;
}

void ColorGhost(int ent, int r, int g, int b)
{
    SetEntityRenderColor(ent, r, g, b, 110);
    if (g_cvGlow.BoolValue)
    {
        SetEntProp(ent, Prop_Send, "m_iGlowType", 3);
        SetEntProp(ent, Prop_Send, "m_nGlowRange", 0);
        SetEntProp(ent, Prop_Send, "m_glowColorOverride", r + (g << 8) + (b << 16));
    }
}

public Action Hook_GhostTransmit(int entity, int client)
{
    return (g_GhostOwner[entity] == client) ? Plugin_Continue : Plugin_Handled;
}

void RemoveGhost(int client)
{
    if (client < 1 || client > MaxClients) return;
    int ghost = EntRefToEntIndex(g_GhostRef[client]);
    if (ghost != INVALID_ENT_REFERENCE)
    {
        g_GhostOwner[ghost] = 0;
        AcceptEntityInput(ghost, "Kill");
    }
    g_GhostRef[client] = -1;
    g_GhostState[client] = 0;
}

/* Building / dismantling */
bool IsBuilding(int client)
{
    if (g_BuildRef[client] == -1) return false;
    if (EntRefToEntIndex(g_BuildRef[client]) == INVALID_ENT_REFERENCE)
    {
        g_BuildRef[client] = -1;
        return false;
    }
    return true;
}

void CancelBuild(int client, bool notify)
{
    if (client < 1 || client > MaxClients) return;
    int ref = g_BuildRef[client];
    if (ref == -1) return;
    g_BuildRef[client] = -1;
    int ent = EntRefToEntIndex(ref);
    if (ent != INVALID_ENT_REFERENCE)
    {
        StopSound(ent, SNDCHAN_AUTO, SND_BUILD);
        AcceptEntityInput(ent, "Kill");
        int idx = FindWireByRef(ref);
        if (idx != -1) EraseWire(idx);
        if (notify && IsClientInGame(client)) PrintCenterText(client, "Construction cancelled.");
    }
}

void StartBuild(int client, int userid, const float pos[3], const float ang[3])
{
    int slot = AllocSlot();
    if (slot == -1)
    {
        PrintHintText(client, "Too many barbed wires on the map right now.");
        return;
    }
    int ent = CreateEntityByName("prop_dynamic_override");
    if (ent == -1)
    {
        g_SlotUsed[slot] = false;
        return;
    }
    SetEntityModel(ent, WIRE_MODEL);
    DispatchKeyValue(ent, "targetname", WIRE_NAME);
    DispatchKeyValue(ent, "solid", "0");
    DispatchSpawn(ent);
    TeleportEntity(ent, pos, ang, NULL_VECTOR);

    float now = GetGameTime();
    float buildTime = g_cvBuildTime.FloatValue;
    WireData w;
    w.ref = EntIndexToEntRef(ent);
    w.slot = slot;
    w.ownerUserId = userid;
    w.builderUserId = userid;
    w.yaw = ang[1];
    w.buildStart = now;
    w.buildEnd = now + buildTime;
    w.done = (buildTime <= 0.0);
    w.alpha = 70;
    w.lastPct = -1;
    for (int i = 0; i < 3; i++) w.pos[i] = pos[i];

    float mins[3], maxs[3];
    GetEntPropVector(ent, Prop_Send, "m_vecMins", mins);
    GetEntPropVector(ent, Prop_Send, "m_vecMaxs", maxs);
    if ((maxs[0] - mins[0]) < 1.0 && (maxs[1] - mins[1]) < 1.0)
    {
        mins[0] = -64.0; mins[1] = -16.0; mins[2] = 0.0;
        maxs[0] = 64.0; maxs[1] = 16.0; maxs[2] = 56.0;
    }
    for (int i = 0; i < 3; i++)
    {
        w.mins[i] = mins[i];
        w.maxs[i] = maxs[i];
    }

    if (w.done)
    {
        SetEntityRenderMode(ent, RENDER_NORMAL);
        SetEntityRenderColor(ent, 255, 255, 255, 255);
        w.alpha = 255;
    }
    else
    {
        SetEntityRenderMode(ent, RENDER_TRANSCOLOR);
        SetEntityRenderColor(ent, 255, 200, 80, w.alpha);
        g_BuildRef[client] = w.ref;
        for (int i = 0; i < 3; i++) g_BuildPos[client][i] = pos[i];
    }
    g_Wires.PushArray(w);
    EmitSoundToAll(SND_BUILD, ent, SNDCHAN_AUTO, SNDLEVEL_NORMAL);
    if (w.done) PrintHintText(client, "Barbed wire placed (%d/%d)", CountOwned(userid), g_cvMaxWires.IntValue);
}

bool RemoveWireAimedAt(const float eye[3], const float fwd[3], float dist)
{
    float pt[3];
    for (float t = 0.0; t <= dist + 8.0; t += 6.0)
    {
        for (int i = 0; i < 3; i++) pt[i] = eye[i] + fwd[i] * t;
        for (int i = g_Wires.Length - 1; i >= 0; i--)
        {
            WireData w;
            g_Wires.GetArray(i, w);
            if (!PointInBox(pt, w.pos, w.yaw, w.mins, w.maxs, 10.0, 6.0, 6.0)) continue;

            EmitSoundToAll(SND_REMOVE, SOUND_FROM_WORLD, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, SNDVOL_NORMAL, SNDPITCH_NORMAL, -1, w.pos);
            int ent = EntRefToEntIndex(w.ref);
            if (ent != INVALID_ENT_REFERENCE)
            {
                StopSound(ent, SNDCHAN_AUTO, SND_BUILD);
                AcceptEntityInput(ent, "Kill");
            }
            EraseWire(i);
            return true;
        }
    }
    return false;
}

bool PointInBox(const float pt[3], const float origin[3], float yaw, const float mins[3], const float maxs[3], float padXY, float zBelow, float zAbove)
{
    float dx = pt[0] - origin[0];
    float dy = pt[1] - origin[1];
    float dz = pt[2] - origin[2];
    float rad = DegToRad(yaw);
    float c = Cosine(rad);
    float s = Sine(rad);
    float lx = dx * c + dy * s;
    float ly = -dx * s + dy * c;
    return (lx >= mins[0] - padXY && lx <= maxs[0] + padXY
         && ly >= mins[1] - padXY && ly <= maxs[1] + padXY
         && dz >= mins[2] - zBelow && dz <= maxs[2] + zAbove);
}

/* Per-frame build progress, target slowdown, and independent damage timers. */
public void OnGameFrame()
{
    if (g_Wires == null) return;
    float now = GetGameTime();

    for (int i = g_Wires.Length - 1; i >= 0; i--)
    {
        WireData w;
        g_Wires.GetArray(i, w);
        int ent = EntRefToEntIndex(w.ref);
        if (ent == INVALID_ENT_REFERENCE)
        {
            EraseWire(i);
            continue;
        }
        if (w.done) continue;

        int builder = GetClientOfUserId(w.builderUserId);
        if (builder < 1 || builder > MaxClients || g_BuildRef[builder] != w.ref)
        {
            StopSound(ent, SNDCHAN_AUTO, SND_BUILD);
            AcceptEntityInput(ent, "Kill");
            EraseWire(i);
            continue;
        }

        if (now >= w.buildEnd)
        {
            w.done = true;
            w.alpha = 255;
            SetEntityRenderMode(ent, RENDER_NORMAL);
            SetEntityRenderColor(ent, 255, 255, 255, 255);
            g_Wires.SetArray(i, w);
            g_BuildRef[builder] = -1;
            PrintHintText(builder, "Barbed wire built (%d/%d)", CountOwned(w.ownerUserId), g_cvMaxWires.IntValue);
            continue;
        }

        float duration = w.buildEnd - w.buildStart;
        if (duration <= 0.0) duration = 0.001;
        float progress = (now - w.buildStart) / duration;
        int a = 70 + RoundToFloor(185.0 * progress);
        int pct = RoundToFloor(progress * 20.0) * 5;
        bool changed = false;
        if (a != w.alpha)
        {
            w.alpha = a;
            SetEntityRenderColor(ent, 255, 200, 80, a);
            changed = true;
        }
        if (pct != w.lastPct)
        {
            w.lastPct = pct;
            PrintCenterText(builder, "Building barbed wire... %d%%", pct);
            changed = true;
        }
        if (changed) g_Wires.SetArray(i, w);
    }

    if (!g_cvEnable.BoolValue || g_Wires.Length == 0)
    {
        if (g_AnySlowed) ResetAllSlows();
        return;
    }

    // Players: survivor slowdown remains m_flLaggedMovementValue-based.
    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsClientInGame(client) || !IsPlayerAlive(client))
        {
            ResetSlow(client);
            continue;
        }
        int team = GetClientTeam(client);
        if (team != TEAM_SURVIVOR && team != TEAM_INFECTED)
        {
            ResetSlow(client);
            continue;
        }
        if (team == TEAM_INFECTED && GetEntProp(client, Prop_Send, "m_isGhost") != 0)
        {
            ResetSlow(client);
            continue;
        }

		// Tanks can take wire damage but are immune to slowdown when enabled.
		if (team == TEAM_INFECTED
			&& GetEntProp(client, Prop_Send, "m_zombieClass") == ZC_TANK
			&& g_cvTankImmune.BoolValue)
		{
			ResetSlow(client);
			continue;
		}

        float pad = 18.0, height = 71.0;
        if (team == TEAM_INFECTED && GetEntProp(client, Prop_Send, "m_zombieClass") == ZC_TANK)
        {
            pad = 32.0;
            height = 78.0;
        }
        float org[3];
        GetClientAbsOrigin(client, org);
        ProcessTarget(client, org, pad, height, (team == TEAM_INFECTED), now);
    }

    // Common infected always get damage and slowdown processing.
    int ent = -1;
    while ((ent = FindEntityByClassname(ent, "infected")) != -1)
    {
        if (!IsValidEntity(ent)) continue;
        if (GetEntProp(ent, Prop_Data, "m_iHealth") <= 0)
        {
            ResetSlow(ent);
            continue;
        }
        float org[3];
        GetEntPropVector(ent, Prop_Send, "m_vecOrigin", org);
        ProcessTarget(ent, org, 14.0, 71.0, true, now);
    }
}

bool IsTargetAlive(int ent)
{
    if (ent <= MaxClients) return IsClientInGame(ent) && IsPlayerAlive(ent);
    return IsValidEntity(ent) && GetEntProp(ent, Prop_Data, "m_iHealth") > 0;
}

void ProcessTarget(int ent, const float org[3], float pad, float height, bool giveOwnerCredit, float now)
{
    int ref = EntIndexToEntRef(ent);
    if (g_TargetRef[ent] != ref)
    {
        g_TargetRef[ent] = ref;
        g_Slowed[ent] = false;
        g_HasLastPos[ent] = false;
        for (int s = 0; s < MAX_WIRES; s++) g_SlotNextDmg[s][ent] = 0.0;
    }

    bool inside = false;
    bool damaged = false;
    bool alive = true;
    float interval = g_cvInterval.FloatValue;
    float damage = g_cvDamage.FloatValue;
    int count = g_Wires.Length;
    for (int i = 0; i < count; i++)
    {
        WireData w;
        g_Wires.GetArray(i, w);
        if (!w.done) continue;
        if (!PointInBox(org, w.pos, w.yaw, w.mins, w.maxs, pad, height, 0.0)) continue;

        inside = true;
        if (now < g_SlotNextDmg[w.slot][ent]) continue;
        g_SlotNextDmg[w.slot][ent] = now + interval;

        int inflictor = EntRefToEntIndex(w.ref);
        if (inflictor == INVALID_ENT_REFERENCE) inflictor = 0;
        int attacker = 0;
        if (giveOwnerCredit)
        {
            int owner = GetClientOfUserId(w.ownerUserId);
            if (owner > 0 && IsClientInGame(owner)) attacker = owner;
        }
        SDKHooks_TakeDamage(ent, inflictor, attacker, damage, DMG_SLASH);
        damaged = true;
        if (!IsTargetAlive(ent))
        {
            alive = false;
            break;
        }
    }

    if (damaged) EmitSoundToAll(SND_DAMAGE, ent, SNDCHAN_AUTO, SNDLEVEL_NORMAL);
	if (!inside || !alive)
	{
		ResetSlow(ent);
		TrackPosition(ent, org);
		return;
	}

	// Tanks remain vulnerable to wire damage but can be immune to slowdown.
	if (ent <= MaxClients
		&& GetClientTeam(ent) == TEAM_INFECTED
		&& GetEntProp(ent, Prop_Send, "m_zombieClass") == ZC_TANK
		&& g_cvTankImmune.BoolValue)
	{
		ResetSlow(ent);
		return;
	}

	ApplySlow(ent);

	if (ent > MaxClients || GetClientTeam(ent) == TEAM_INFECTED)
		EnforceSlow(ent, org, ent > MaxClients || GetClientTeam(ent) == TEAM_INFECTED);
	else
		TrackPosition(ent, org);
}

void TrackPosition(int ent, const float org[3])
{
    if (ent <= MaxClients || ent < 1 || ent > 2048) return;
    for (int i = 0; i < 3; i++) g_LastPos[ent][i] = org[i];
    g_HasLastPos[ent] = true;
}

void EnforceSlow(int ent, const float org[3], bool isInfectedTeam)
{
    float scale = g_cvSlow.FloatValue;

    // Player-controlled infected use the normal movement multiplier plus an optional velocity cap.
    if (ent <= MaxClients)
    {
        if (!isInfectedTeam || scale >= 0.999) return;
        float maxSpeed = GetEntPropFloat(ent, Prop_Data, "m_flMaxspeed");
        if (maxSpeed <= 1.0) maxSpeed = 300.0;
        float cap = maxSpeed * scale;
        float vel[3];
        GetEntPropVector(ent, Prop_Data, "m_vecVelocity", vel);
        float speed = SquareRoot(vel[0] * vel[0] + vel[1] * vel[1]);
        if (speed > cap && speed > 0.0)
        {
            float factor = cap / speed;
            vel[0] *= factor;
            vel[1] *= factor;
            TeleportEntity(ent, NULL_VECTOR, NULL_VECTOR, vel);
        }
        return;
    }

    // Common infected are NextBots; actual horizontal displacement is scaled each server frame.
    if (scale >= 0.999)
    {
        TrackPosition(ent, org);
        return;
    }
    if (!g_HasLastPos[ent])
    {
        TrackPosition(ent, org);
        return;
    }

    float dx = org[0] - g_LastPos[ent][0];
    float dy = org[1] - g_LastPos[ent][1];
    float moved = SquareRoot(dx * dx + dy * dy);

    // Do not pull an infected backward across the map after a teleport/unstuck operation.
    if (moved > 256.0 || moved <= 0.01)
    {
        TrackPosition(ent, org);
        return;
    }

    float newPos[3];
    newPos[0] = g_LastPos[ent][0] + dx * scale;
    newPos[1] = g_LastPos[ent][1] + dy * scale;
    newPos[2] = org[2];
    TeleportEntity(ent, newPos, NULL_VECTOR, NULL_VECTOR);
    for (int i = 0; i < 3; i++) g_LastPos[ent][i] = newPos[i];
    g_HasLastPos[ent] = true;
}

void ApplySlow(int ent)
{
    float scale = g_cvSlow.FloatValue;
    g_Slowed[ent] = true;
    g_AnySlowed = true;

    if (ent <= MaxClients)
    {
        // Preserve original player slowdown behavior for survivors and infected players.
        SetEntPropFloat(ent, Prop_Send, "m_flLaggedMovementValue", scale);
        return;
    }

    // Supplemental only for common infected; position correction is the authoritative slow.
    if (HasEntProp(ent, Prop_Send, "m_flPlaybackRate"))
        SetEntPropFloat(ent, Prop_Send, "m_flPlaybackRate", scale);
    if (HasEntProp(ent, Prop_Send, "m_flLaggedMovementValue"))
        SetEntPropFloat(ent, Prop_Send, "m_flLaggedMovementValue", scale);
}

void ResetSlow(int ent)
{
    if (ent < 1 || ent > 2048 || !g_Slowed[ent]) return;
    g_Slowed[ent] = false;

    if (ent <= MaxClients)
    {
        if (IsClientInGame(ent)) SetEntPropFloat(ent, Prop_Send, "m_flLaggedMovementValue", 1.0);
        return;
    }
    if (!IsValidEntity(ent) || EntIndexToEntRef(ent) != g_TargetRef[ent]) return;
    if (HasEntProp(ent, Prop_Send, "m_flPlaybackRate"))
        SetEntPropFloat(ent, Prop_Send, "m_flPlaybackRate", 1.0);
    if (HasEntProp(ent, Prop_Send, "m_flLaggedMovementValue"))
        SetEntPropFloat(ent, Prop_Send, "m_flLaggedMovementValue", 1.0);
    g_HasLastPos[ent] = false;
}

void ResetAllSlows()
{
    for (int i = 1; i <= 2048; i++)
    {
        if (g_Slowed[i]) ResetSlow(i);
    }
    g_AnySlowed = false;
}