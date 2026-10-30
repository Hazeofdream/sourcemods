#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <left4dhooks>

#define MAX_EDICTS		2049
#define TEAM_SURVIVOR	2
#define TEAM_INFECTED	3

#define REFLECT_IMMUNE	0.5		// a fresh reflected rock ignores melee this long (the same swing can't send it back)
#define SHAKE_BLOCK		0.75	// screen shake is blocked this long after a player reflects a rock
#define KILL_FALLBACK	0.5		// a shattered rock that somehow survives is removed after this long

// Per-edict rock state
enum
{
	Rock_None = 0,
	Rock_Reflected,		// sent back by a survivor: hits infected, never survivors
	Rock_Breaking,		// reflected rock that hit an infected and is being shattered (still harmless to survivors)
	Rock_Spent			// original rock that was reflected: ignores all damage until removed
}

ConVar g_cvEnabled, g_cvDamage, g_cvHitbox, g_cvNoShake, g_cvDebug;
bool  g_bEnabled, g_bNoShake, g_bDebug;
float g_fDamage, g_fHitboxSqr;

ArrayList g_hRocks;						// entity refs of rocks in Rock_Reflected state
int   g_iState[MAX_EDICTS];
int   g_iReflector[MAX_EDICTS];			// userid of the survivor who reflected the rock
float g_fReflectTime[MAX_EDICTS];
float g_fLastReflect[MAXPLAYERS + 1];

public Plugin myinfo =
{
	name        = "Parry This",
	author      = "Haze_of_dream",
	description = "Reflect Tank rocks back with melee weapons",
	version     = "1.1",
	url         = ""
};

public void OnPluginStart()
{
	if (GetEngineVersion() != Engine_Left4Dead2)
		SetFailState("This plugin only supports Left 4 Dead 2.");

	g_cvEnabled = CreateConVar("parrythis_enable",  "1",       "Enable Tank rock reflecting with melee weapons", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvDamage  = CreateConVar("parrythis_damage",  "15000.0", "Damage a reflected rock deals to the infected it hits", FCVAR_NOTIFY, true, 0.0);
	g_cvHitbox  = CreateConVar("parrythis_hitbox",  "80.0",    "Radius (in units) around a reflected rock that counts as hitting an infected", FCVAR_NOTIFY, true, 1.0);
	g_cvNoShake = CreateConVar("parrythis_noshake", "1",       "Block screen shake on the player who just reflected a rock", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvDebug   = CreateConVar("parrythis_debug",   "0",       "Print reflect debug info to the swinging player's chat", FCVAR_NONE, true, 0.0, true, 1.0);

	g_cvEnabled.AddChangeHook(OnCvarChanged);
	g_cvDamage.AddChangeHook(OnCvarChanged);
	g_cvHitbox.AddChangeHook(OnCvarChanged);
	g_cvNoShake.AddChangeHook(OnCvarChanged);
	g_cvDebug.AddChangeHook(OnCvarChanged);

	AutoExecConfig(true, "parrythis");
	ReadCvars();

	g_hRocks = new ArrayList();

	UserMsg shakeMsg = GetUserMessageId("Shake");
	if (shakeMsg != INVALID_MESSAGE_ID)
		HookUserMessage(shakeMsg, Hook_Shake, true);
	else
		LogError("Could not find the Shake user message; parrythis_noshake will have no effect.");

	// Late load
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i))
			OnClientPutInServer(i);
	}

	int rock = -1;
	while ((rock = FindEntityByClassname(rock, "tank_rock")) != -1)
		SDKHook(rock, SDKHook_OnTakeDamage, Rock_OnTakeDamage);
}

public void OnConfigsExecuted()
{
	ReadCvars();
}

void OnCvarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	ReadCvars();
}

void ReadCvars()
{
	g_bEnabled = g_cvEnabled.BoolValue;
	g_fDamage  = g_cvDamage.FloatValue;
	g_bNoShake = g_cvNoShake.BoolValue;
	g_bDebug   = g_cvDebug.BoolValue;

	float r = g_cvHitbox.FloatValue;
	g_fHitboxSqr = r * r;
}

// Suppress screen shake for anyone who reflected a rock in the last moment.
Action Hook_Shake(UserMsg msg_id, BfRead msg, const int[] players, int playersNum, bool reliable, bool init)
{
	if (!g_bNoShake)
		return Plugin_Continue;

	float now = GetGameTime();
	for (int i = 0; i < playersNum; i++)
	{
		int client = players[i];
		if (client >= 1 && client <= MaxClients && now - g_fLastReflect[client] < SHAKE_BLOCK)
			return Plugin_Handled;
	}
	return Plugin_Continue;
}

public void OnClientPutInServer(int client)
{
	g_fLastReflect[client] = 0.0;
	SDKHook(client, SDKHook_OnTakeDamage, Client_OnTakeDamage);
}

bool IsReflected(int rock)
{
	return rock > MaxClients && rock < MAX_EDICTS && (g_iState[rock] == Rock_Reflected || g_iState[rock] == Rock_Breaking);
}

// A reflected rock must never hurt a survivor, including the one who reflected it.
Action Client_OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype)
{
	if (IsReflected(inflictor) && GetClientTeam(victim) == TEAM_SURVIVOR)
		return Plugin_Handled;
	return Plugin_Continue;
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if (entity > MaxClients && entity < MAX_EDICTS && classname[0] == 't' && StrEqual(classname, "tank_rock"))
		SDKHook(entity, SDKHook_OnTakeDamage, Rock_OnTakeDamage);
}

public void OnEntityDestroyed(int entity)
{
	if (entity > MaxClients && entity < MAX_EDICTS)
		g_iState[entity] = Rock_None;
}

// ---------------------------------------------------------------------------
// A melee weapon hit on a rock spawns a reflected rock with reversed velocity.
// ---------------------------------------------------------------------------
Action Rock_OnTakeDamage(int rock, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon, float damageForce[3], float damagePosition[3])
{
	if (!g_bEnabled || rock >= MAX_EDICTS)
		return Plugin_Continue;

	switch (g_iState[rock])
	{
		// Our own shatter damage after a reflected rock hits an infected: let it through
		case Rock_Breaking:  return Plugin_Continue;
		// Already reflected: swallow extra damage so it can't spawn duplicates or break
		case Rock_Spent:     return Plugin_Handled;
		case Rock_Reflected:
		{
			if (GetGameTime() - g_fReflectTime[rock] < REFLECT_IMMUNE)
				return Plugin_Handled;
		}
	}

	if (attacker < 1 || attacker > MaxClients || !IsClientInGame(attacker) || GetClientTeam(attacker) != TEAM_SURVIVOR)
		return Plugin_Continue;

	if (weapon <= MaxClients || !IsValidEntity(weapon))
		return Plugin_Continue;

	char cls[16];
	GetEntityClassname(weapon, cls, sizeof(cls));
	if (!StrEqual(cls, "weapon_melee"))
		return Plugin_Continue;

	float vel[3], origin[3];
	GetEntPropVector(rock, Prop_Data, "m_vecVelocity", vel);
	GetEntPropVector(rock, Prop_Data, "m_vecAbsOrigin", origin);

	// Ignore a rock that isn't moving (e.g. still held by the Tank)
	if (GetVectorLength(vel, true) < 1.0)
	{
		Debug(attacker, "rock %d hit by melee but has no velocity, ignored", rock);
		return Plugin_Continue;
	}

	int projectile = L4D_TankRockPrj(attacker, origin, NULL_VECTOR);
	if (projectile <= MaxClients || projectile >= MAX_EDICTS || !IsValidEntity(projectile))
	{
		Debug(attacker, "rock %d: failed to spawn the reflected rock", rock);
		return Plugin_Continue;
	}

	NegateVector(vel);
	TeleportEntity(projectile, origin, NULL_VECTOR, vel);

	float now = GetGameTime();
	g_iState[projectile]       = Rock_Reflected;
	g_fReflectTime[projectile] = now;
	g_iReflector[projectile]   = GetClientUserId(attacker);
	g_fLastReflect[attacker]   = now;
	SDKHook(projectile, SDKHook_Touch, Rock_Touch);
	g_hRocks.Push(EntIndexToEntRef(projectile));

	Debug(attacker, "rock %d REFLECTED as rock %d", rock, projectile);

	// Retire the original: hide it and park it far away so any break effect or sound from its removal
	// plays out of sight, then remove it next frame.
	g_iState[rock] = Rock_Spent;
	SetEntityRenderMode(rock, RENDER_NONE);

	origin[2] += 5000.0;
	TeleportEntity(rock, origin, NULL_VECTOR, view_as<float>({0.0, 0.0, 0.0}));

	RequestFrame(Frame_KillRock, EntIndexToEntRef(rock));
	return Plugin_Handled;
}

void Frame_KillRock(int ref)
{
	KillRef(ref);
}

Action Timer_KillRock(Handle timer, int ref)
{
	KillRef(ref);
	return Plugin_Stop;
}

void KillRef(int ref)
{
	int ent = EntRefToEntIndex(ref);
	if (ent > MaxClients)
		RemoveEntity(ent);
}

// ---------------------------------------------------------------------------
// Rocks don't reliably fire touch events against infected, so reflected rocks
// are also checked for nearby infected every frame.
// ---------------------------------------------------------------------------
public void OnGameFrame()
{
	for (int i = g_hRocks.Length - 1; i >= 0; i--)
	{
		int rock = EntRefToEntIndex(g_hRocks.Get(i));

		if (rock == INVALID_ENT_REFERENCE)
		{
			g_hRocks.Erase(i);
			continue;
		}

		// Consumed by the touch hook (or shattering)
		if (g_iState[rock] != Rock_Reflected)
		{
			g_hRocks.Erase(i);
			continue;
		}

		float pos[3];
		GetEntPropVector(rock, Prop_Data, "m_vecAbsOrigin", pos);

		int victim = FindInfectedNear(pos);
		if (victim != -1)
			HitInfected(rock, victim);	// erases the rock from the list
	}
}

// Living special infected (non-ghost), commons or witches whose center is within the hitbox radius.
int FindInfectedNear(const float pos[3])
{
	float center[3];

	for (int client = 1; client <= MaxClients; client++)
	{
		if (!IsClientInGame(client) || GetClientTeam(client) != TEAM_INFECTED || !IsPlayerAlive(client)
			|| GetEntProp(client, Prop_Send, "m_isGhost"))
			continue;

		GetClientAbsOrigin(client, center);
		if (InHitbox(pos, center))
			return client;
	}

	int ent = FindNearByClass(pos, "infected");
	return (ent != -1) ? ent : FindNearByClass(pos, "witch");
}

int FindNearByClass(const float pos[3], const char[] classname)
{
	float center[3];
	int ent = -1;
	while ((ent = FindEntityByClassname(ent, classname)) != -1)
	{
		if (GetEntProp(ent, Prop_Data, "m_lifeState") != 0)
			continue;

		GetEntPropVector(ent, Prop_Data, "m_vecAbsOrigin", center);
		if (InHitbox(pos, center))
			return ent;
	}
	return -1;
}

// center = the target's feet; its body center is 36 units up.
bool InHitbox(const float pos[3], float center[3])
{
	center[2] += 36.0;
	return GetVectorDistance(pos, center, true) <= g_fHitboxSqr;
}

// ---------------------------------------------------------------------------
// Only reflected rocks are hooked here.
// ---------------------------------------------------------------------------
Action Rock_Touch(int rock, int other)
{
	// World / props: let the game shatter the rock normally
	if (!g_bEnabled || other <= 0 || !IsReflected(rock))
		return Plugin_Continue;

	if (other <= MaxClients)
	{
		if (!IsClientInGame(other) || !IsPlayerAlive(other))
			return Plugin_Continue;

		switch (GetClientTeam(other))
		{
			// Pass through survivors, no friendly fire
			case TEAM_SURVIVOR: return Plugin_Handled;
			case TEAM_INFECTED:
			{
				if (!GetEntProp(other, Prop_Send, "m_isGhost"))
					HitInfected(rock, other);
				return Plugin_Handled;
			}
		}
		return Plugin_Continue;
	}

	char cls[16];
	GetEntityClassname(other, cls, sizeof(cls));
	if (StrEqual(cls, "infected") || StrEqual(cls, "witch"))
	{
		HitInfected(rock, other);
		return Plugin_Handled;
	}
	return Plugin_Continue;
}

void HitInfected(int rock, int victim)
{
	if (g_iState[rock] != Rock_Reflected)
		return;

	int attacker = GetReflector(rock);

	SDKHooks_TakeDamage(victim, rock, attacker, g_fDamage, DMG_CRUSH);

	if (g_bDebug && attacker > 0)
	{
		char cls[32];
		GetEntityClassname(victim, cls, sizeof(cls));
		Debug(attacker, "rock %d hit %s (entity %d) for %.0f damage", rock, cls, victim, g_fDamage);
	}

	// Shatter the rock with the game's own break effect by damaging it. Rock_Breaking still counts as
	// reflected, so it can't hurt survivors until it's gone.
	g_iState[rock] = Rock_Breaking;

	int idx = g_hRocks.FindValue(EntIndexToEntRef(rock));
	if (idx != -1)
		g_hRocks.Erase(idx);

	SDKHooks_TakeDamage(rock, attacker, attacker, 1000.0, DMG_BULLET);

	// Fallback in case the rock survives the damage
	CreateTimer(KILL_FALLBACK, Timer_KillRock, EntIndexToEntRef(rock), TIMER_FLAG_NO_MAPCHANGE);
}

/**
 * The survivor credited with a reflected rock's damage and kills. Normally the player who reflected it; if they
 * went idle while it was in flight, the bot now playing their survivor. 0 (world) if they left or changed team,
 * so the hit is never credited to a spectator or an infected player.
 */
int GetReflector(int rock)
{
	int userid = g_iReflector[rock];
	int client = GetClientOfUserId(userid);
	if (client == 0)
		return 0;

	if (GetClientTeam(client) == TEAM_SURVIVOR && IsPlayerAlive(client))
		return client;

	for (int bot = 1; bot <= MaxClients; bot++)
	{
		if (IsClientInGame(bot) && IsFakeClient(bot) && GetClientTeam(bot) == TEAM_SURVIVOR
			&& HasEntProp(bot, Prop_Send, "m_humanSpectatorUserID")
			&& GetEntProp(bot, Prop_Send, "m_humanSpectatorUserID") == userid)
			return bot;
	}

	return (GetClientTeam(client) == TEAM_SURVIVOR) ? client : 0;
}

void Debug(int client, const char[] fmt, any ...)
{
	if (!g_bDebug)
		return;

	char buffer[192];
	VFormat(buffer, sizeof(buffer), fmt, 3);
	PrintToChat(client, "[parrythis] %s", buffer);
}