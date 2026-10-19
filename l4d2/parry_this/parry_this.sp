#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <left4dhooks>

#define MAX_EDICTS     2049

ConVar g_cvEnabled;
ConVar g_cvDamage;
ConVar g_cvHitbox;
ConVar g_cvNoShake;
ConVar g_cvDebug;

ArrayList g_hRocks; // blocks of {entity ref, reflector userid} for live reflected rocks
bool  g_bReflected[MAX_EDICTS];
bool  g_bBreaking[MAX_EDICTS]; // reflected rock that has hit an infected and is being shattered
bool  g_bSpent[MAX_EDICTS]; // original rock already reflected; ignore all further damage to it
float g_fReflectTime[MAX_EDICTS]; // game time the rock was reflected
float g_fLastReflect[MAXPLAYERS + 1]; // game time each player last reflected a rock
int  g_iparrythisor[MAX_EDICTS]; // userid of the survivor who reflected it

public Plugin myinfo =
{
	name        = "Parry This",
	author      = "Haze_of_dream",
	description = "Reflect Tank rocks back with melee weapons",
	version     = "1.0",
	url         = ""
};

public void OnPluginStart()
{
	if (GetEngineVersion() != Engine_Left4Dead2)
	{
		SetFailState("This plugin only supports Left 4 Dead 2.");
	}

	g_cvEnabled = CreateConVar("parrythis_enable", "1",     "Enable Tank rock reflecting with melee weapons (1 = on, 0 = off)", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvDamage  = CreateConVar("parrythis_damage", "300.0", "Damage a reflected rock deals to the infected it hits", FCVAR_NOTIFY, true, 0.0);
	g_cvHitbox  = CreateConVar("parrythis_hitbox", "80.0",  "Radius (in units) around a reflected rock that counts as hitting an infected", FCVAR_NOTIFY, true, 1.0);
	g_cvNoShake = CreateConVar("parrythis_noshake", "1",    "Block screen shake on the player who just reflected a rock (1 = on, 0 = off)", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvDebug   = CreateConVar("parrythis_debug",  "0",     "Print reflect debug info to the swinging player's chat (1 = on)", FCVAR_NONE, true, 0.0, true, 1.0);

	g_hRocks = new ArrayList(2);

	UserMsg shakeMsg = GetUserMessageId("Shake");
	if (shakeMsg != INVALID_MESSAGE_ID)
		HookUserMessage(shakeMsg, Hook_Shake, true);
	else
		LogError("Could not find the Shake user message; parrythis_noshake will have no effect.");

	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i))
			SDKHook(i, SDKHook_OnTakeDamage, Client_OnTakeDamage);
	}

	AutoExecConfig(true, "parrythis");
}

// Suppress screen shake for anyone who reflected a rock in the last moment.
public Action Hook_Shake(UserMsg msg_id, BfRead msg, const int[] players, int playersNum, bool reliable, bool init)
{
	if (!g_cvNoShake.BoolValue)
		return Plugin_Continue;

	float now = GetGameTime();
	for (int i = 0; i < playersNum; i++)
	{
		int client = players[i];
		if (client >= 1 && client <= MaxClients && (now - g_fLastReflect[client]) < 0.75)
			return Plugin_Handled;
	}

	return Plugin_Continue;
}

public void OnClientPutInServer(int client)
{
	g_fLastReflect[client] = 0.0;
	SDKHook(client, SDKHook_OnTakeDamage, Client_OnTakeDamage);
}

// A reflected rock must never hurt a survivor, including the one who reflected it.
public Action Client_OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype)
{
	if (inflictor > MaxClients && inflictor < MAX_EDICTS && g_bReflected[inflictor]
		&& IsClientInGame(victim) && GetClientTeam(victim) == 2)
	{
		return Plugin_Handled;
	}

	return Plugin_Continue;
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if (entity <= MaxClients || entity >= MAX_EDICTS)
		return;

	if (classname[0] != 't')
		return;

	if (StrEqual(classname, "tank_rock"))
		SDKHook(entity, SDKHook_OnTakeDamage, Rock_OnTakeDamage);
}

public void OnEntityDestroyed(int entity)
{
	if (entity > MaxClients && entity < MAX_EDICTS)
	{
		g_bReflected[entity]     = false;
		g_iparrythisor[entity] = 0;
		g_fReflectTime[entity]   = 0.0;
		g_bSpent[entity]         = false;
		g_bBreaking[entity]      = false;
	}
}

// ---------------------------------------------------------------------------
// A melee weapon hit on a rock spawns a reflected rock with reversed velocity.
// ---------------------------------------------------------------------------
public Action Rock_OnTakeDamage(int rock, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon, float damageForce[3], float damagePosition[3])
{
	if (!g_cvEnabled.BoolValue)
		return Plugin_Continue;

	// Our own shatter damage after a reflected rock hits an infected: let it through
	if (rock < MAX_EDICTS && g_bBreaking[rock])
		return Plugin_Continue;

	// The original rock was already reflected this swing; swallow any extra
	// damage events so it can't spawn duplicates or break.
	if (rock < MAX_EDICTS && g_bSpent[rock])
		return Plugin_Handled;

	// A freshly reflected rock is immune to melee briefly, so the same swing
	// can't hit it again and send it straight back.
	if (rock < MAX_EDICTS && g_bReflected[rock] && (GetGameTime() - g_fReflectTime[rock]) < 0.5)
		return Plugin_Handled;

	if (attacker < 1 || attacker > MaxClients || !IsClientInGame(attacker) || GetClientTeam(attacker) != 2)
		return Plugin_Continue;

	if (weapon <= MaxClients || !IsValidEntity(weapon))
		return Plugin_Continue;

	char weaponName[64];
	GetEntityClassname(weapon, weaponName, sizeof(weaponName));
	if (!StrEqual(weaponName, "weapon_melee"))
		return Plugin_Continue;

	float rockVelocity[3], rockOrigin[3];
	GetEntPropVector(rock, Prop_Data, "m_vecVelocity", rockVelocity);
	GetEntPropVector(rock, Prop_Data, "m_vecAbsOrigin", rockOrigin);

	// Ignore a rock that isn't moving (e.g. still held by the Tank)
	if (GetVectorLength(rockVelocity) < 1.0)
	{
		Debug(attacker, "rock %d hit by melee but has no velocity, ignored", rock);
		return Plugin_Continue;
	}

	rockVelocity[0] = -rockVelocity[0];
	rockVelocity[1] = -rockVelocity[1];
	rockVelocity[2] = -rockVelocity[2];

	int projectile = L4D_TankRockPrj(attacker, rockOrigin, NULL_VECTOR);
	if (projectile <= MaxClients || !IsValidEntity(projectile))
	{
		Debug(attacker, "rock %d: failed to spawn the reflected rock", rock);
		return Plugin_Continue;
	}

	TeleportEntity(projectile, rockOrigin, NULL_VECTOR, rockVelocity);

	if (projectile < MAX_EDICTS)
	{
		g_bReflected[projectile]     = true;
		g_fReflectTime[projectile]   = GetGameTime();
		g_fLastReflect[attacker]     = GetGameTime();
		g_iparrythisor[projectile] = GetClientUserId(attacker);
		SDKHook(projectile, SDKHook_Touch, Rock_Touch);
		int idx = g_hRocks.Push(EntIndexToEntRef(projectile));
		g_hRocks.Set(idx, GetClientUserId(attacker), 1);
	}

	Debug(attacker, "rock %d REFLECTED as rock %d", rock, projectile);

	// Retire the original right away: mark it spent and hide it, then remove it next frame
	if (rock < MAX_EDICTS)
		g_bSpent[rock] = true;

	// Hide it and park it far away so any break effect or sound from its removal
	// plays out of sight instead of in front of the player.
	SetEntityRenderMode(rock, RENDER_NONE);

	float parked[3];
	float still[3] = {0.0, 0.0, 0.0};
	parked[0] = rockOrigin[0];
	parked[1] = rockOrigin[1];
	parked[2] = rockOrigin[2] + 5000.0;
	TeleportEntity(rock, parked, NULL_VECTOR, still);

	RequestFrame(Frame_KillRock, EntIndexToEntRef(rock));
	return Plugin_Handled;
}

public void Frame_KillRock(int ref)
{
	int rock = EntRefToEntIndex(ref);
	if (rock != INVALID_ENT_REFERENCE && rock > MaxClients)
		AcceptEntityInput(rock, "Kill");
}

// ---------------------------------------------------------------------------
// Rocks don't reliably fire touch events against infected, so reflected rocks
// are also checked for nearby infected every frame.
// ---------------------------------------------------------------------------
public void OnGameFrame()
{
	if (g_hRocks.Length == 0)
		return;

	float radius = g_cvHitbox.FloatValue;

	for (int i = g_hRocks.Length - 1; i >= 0; i--)
	{
		int rock   = EntRefToEntIndex(g_hRocks.Get(i, 0));
		int client = GetClientOfUserId(g_hRocks.Get(i, 1));

		if (rock == INVALID_ENT_REFERENCE || rock >= MAX_EDICTS)
		{
			if (client > 0)
				Debug(client, "reflected rock is gone without hitting an infected (broke on the world or was removed)");
			g_hRocks.Erase(i);
			continue;
		}

		// Already consumed by the touch hook
		if (!g_bReflected[rock])
		{
			g_hRocks.Erase(i);
			continue;
		}

		float pos[3];
		GetEntPropVector(rock, Prop_Data, "m_vecAbsOrigin", pos);

		int victim = FindInfectedNear(pos, radius);
		if (victim != -1)
			HitInfected(rock, victim);
	}
}

int FindInfectedNear(const float pos[3], float radius)
{
	float center[3];

	// Special infected / Tanks
	for (int client = 1; client <= MaxClients; client++)
	{
		if (!IsClientInGame(client) || !IsPlayerAlive(client) || GetClientTeam(client) != 3)
			continue;

		if (GetEntProp(client, Prop_Send, "m_isGhost") == 1)
			continue;

		GetClientAbsOrigin(client, center);
		center[2] += 36.0;
		if (GetVectorDistance(pos, center) <= radius)
			return client;
	}

	// Commons and witches
	int ent = -1;
	while ((ent = FindEntityByClassname(ent, "infected")) != -1)
	{
		if (GetEntProp(ent, Prop_Data, "m_lifeState") != 0)
			continue;

		GetEntPropVector(ent, Prop_Data, "m_vecAbsOrigin", center);
		center[2] += 36.0;
		if (GetVectorDistance(pos, center) <= radius)
			return ent;
	}

	ent = -1;
	while ((ent = FindEntityByClassname(ent, "witch")) != -1)
	{
		if (GetEntProp(ent, Prop_Data, "m_lifeState") != 0)
			continue;

		GetEntPropVector(ent, Prop_Data, "m_vecAbsOrigin", center);
		center[2] += 36.0;
		if (GetVectorDistance(pos, center) <= radius)
			return ent;
	}

	return -1;
}

// ---------------------------------------------------------------------------
// Only reflected rocks are hooked here.
// ---------------------------------------------------------------------------
public Action Rock_Touch(int rock, int other)
{
	if (!g_cvEnabled.BoolValue || rock >= MAX_EDICTS || !g_bReflected[rock])
		return Plugin_Continue;

	// World / props: let the game shatter the rock normally
	if (other <= 0)
		return Plugin_Continue;

	if (other <= MaxClients)
	{
		if (!IsClientInGame(other) || !IsPlayerAlive(other))
			return Plugin_Continue;

		int team = GetClientTeam(other);

		// Pass through survivors, no friendly fire
		if (team == 2)
			return Plugin_Handled;

		if (team == 3)
		{
			if (GetEntProp(other, Prop_Send, "m_isGhost") == 1)
				return Plugin_Handled;

			HitInfected(rock, other);
			return Plugin_Handled;
		}

		return Plugin_Continue;
	}

	if (IsValidEntity(other))
	{
		char cls[16];
		GetEntityClassname(other, cls, sizeof(cls));
		if (StrEqual(cls, "infected") || StrEqual(cls, "witch"))
		{
			HitInfected(rock, other);
			return Plugin_Handled;
		}
	}

	return Plugin_Continue;
}

void HitInfected(int rock, int victim)
{
	if (rock >= MAX_EDICTS || g_bBreaking[rock])
		return;

	int attacker = GetClientOfUserId(g_iparrythisor[rock]);
	if (attacker < 1 || !IsClientInGame(attacker))
		attacker = 0;

	char cls[32];
	GetEntityClassname(victim, cls, sizeof(cls));

	SDKHooks_TakeDamage(victim, rock, attacker, g_cvDamage.FloatValue, DMG_CRUSH);

	if (attacker > 0)
	{
		if (victim <= MaxClients)
		{
			char name[MAX_NAME_LENGTH];
			GetClientName(victim, name, sizeof(name));
			Debug(attacker, "rock %d hit %s '%s' (entity %d, team %d) for %.0f damage", rock, cls, name, victim, GetClientTeam(victim), g_cvDamage.FloatValue);
		}
		else
		{
			Debug(attacker, "rock %d hit %s (entity %d) for %.0f damage", rock, cls, victim, g_cvDamage.FloatValue);
		}
	}

	// Shatter the rock with the game's own break effect by damaging it. It stays
	// marked as reflected until it's gone so it still can't hurt survivors.
	g_bBreaking[rock] = true;

	int idx = g_hRocks.FindValue(EntIndexToEntRef(rock), 0);
	if (idx != -1)
		g_hRocks.Erase(idx);

	SDKHooks_TakeDamage(rock, attacker, attacker, 1000.0, DMG_BULLET);

	// Fallback in case the rock survives the damage
	CreateTimer(0.5, Timer_KillRock, EntIndexToEntRef(rock), TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_KillRock(Handle timer, int ref)
{
	int rock = EntRefToEntIndex(ref);
	if (rock != INVALID_ENT_REFERENCE && rock > MaxClients)
		AcceptEntityInput(rock, "Kill");

	return Plugin_Stop;
}

void Debug(int client, const char[] fmt, any ...)
{
	if (!g_cvDebug.BoolValue)
		return;

	char buffer[192];
	VFormat(buffer, sizeof(buffer), fmt, 3);
	PrintToChat(client, "[parrythis] %s", buffer);
}