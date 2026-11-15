/**
 * [L4D2] Fortifications
 *
 * Use the CSS knife as a construction tool. Buildable fortifications:
 *   - Barbed Wire : damages and slows anything that touches it
 *   - Bremer Wall : solid concrete wall
 *   - .50 Cal     : a real, usable prop_minigun (.50 cal) turret
 *   - Minigun     : a real, usable minigun turret
 *   - Barricade   : solid plastic and metal barrier, quicker to build than a Bremer wall. Topped with barbed wire
 *                   that works like normal barbed wire but is part of the barricade, not a build of its own
 *
 * Place a blueprint, then build it up by swinging at it:
 *    Hold +walk and press +zoom : toggle BUILD MODE (placement hologram)
 *    In build mode:
 *       MOUSE1 (+attack)  : place a blueprint instantly (no-collide, non-functional). Attacks are blocked.
 *       +zoom             : change fortification type
 *       Reload            : toggle placement rotation 0 / 90
 *    Out of build mode:
 *       MOUSE1 (+attack)  : attack as normal. Swinging at a blueprint builds it. Hitting the red crit marker
 *                           gives big progress (1 crit = barbed wire, 2 = barricade, 4 = Bremer wall, 8 = .50 cal);
 *                           missing the marker still builds at a reduced rate.
 *    Any time:
 *       +attack2 (HOLD, shove) : dismantle what you are aiming at (each type has its own dismantle time)
 *       +walk and +use         : show how many fortifications you have, and your limits
 *    Blueprints become more opaque (and glow when nearly done) as they get built. Finished walls become solid,
 *    finished wire and .50 cals become functional. Blueprints are never removed for being far away.
 *
 * Crit markers sit on the buildable's real collision surface, stay put while valid, and after a hit
 * jump along a line (sm_fortifications_marker_move) so you have to walk around the buildable to follow it.
 * Each buildable can be turned off with sm_<name>_enable.
 * Guidance hints are off by default (sm_fortifications_hints 1 turns them on).
 *
 * Every player can have sm_fortifications_max (default 6) fortifications at a time.
 * Building past the limit destroys that player's oldest fortification. Each player may only have
 * sm_50cal_max (default 1) .50 cal at a time.
 *
 * Commands:
 *   sm_fortifications      - gives you the CSS knife (the construction tool)
 *   sm_clearfortifications - (admin, ADMFLAG_SLAY) removes every fortification
 *
 * Placement is refused in the start area, saferooms and rescue closets, in mid air, and through walls.
 *
 * Requires: SourceMod 1.10+ (enum structs), SDKTools, SDKHooks. Optional: left4dhooks (safe zone / spawn area check)
 */

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#undef REQUIRE_PLUGIN
#include <left4dhooks>
#define REQUIRE_PLUGIN

#define PLUGIN_VERSION	"1.2.1"

// ---- Models ----------------------------------------------------------
#define MODEL_WIRE		"models/props_fortifications/barricade_razorwire001_128_reference.mdl"
#define MODEL_WALL		"models/props_fortifications/concrete_wall001_96_reference.mdl"
#define MODEL_CAL		"models/w_models/weapons/50cal.mdl"
#define MODEL_MINIGUN	"models/w_models/weapons/w_minigun.mdl"
#define MODEL_BARRICADE	"models/props_fortifications/barricade001_128_reference.mdl"

// ---- Construction tool (melee script name + its assets) --------------
#define TOOL_MELEE		"baseball_bat"
#define TOOL_V_MODEL	"models/v_models/v_baseball_bat.mdl"
#define TOOL_W_MODEL	"models/w_models/weapons/w_baseball_bat.mdl"
#define TOOL_SCRIPT		"scripts/melee/" ... TOOL_MELEE ... ".txt"

// Crit markers are drawn with temp-entity beams, which are sent only to the player they belong to
#define BEAM_MATERIAL	"materials/sprites/laserbeam.vmt"

// ---- Crit marker look (R, G, B, A) ----------------------------------
#define MARKER_COLOR		{246, 220, 38, 255}		// marker in view
#define MARKER_COLOR_AIMED	{82, 83, 79, 255}		// crosshair is on it and in reach: swinging now is a crit
#define MARKER_SIZE			3.0						// length of each arm of the X from its center (units)
#define MARKER_WIDTH		1.0						// beam thickness (units)

// Crit markers are only placed / moved inside this part of the player's view (degrees from the crosshair),
// so they never land off screen or jump above what the player can see.
#define MARKER_VIEW_SIDE	40.0
#define MARKER_VIEW_UP		20.0
#define MARKER_VIEW_DOWN	30.0

// Melee impact sounds are muted for this long after a swing aimed at a fortification.
#define MUTE_HIT_TIME		0.6

// ---- Sounds (relative to the sound/ folder) --------------------------
#define SND_WIRE_DAMAGE		"physics/metal/metal_chainlink_impact_soft2.wav"
#define SND_WIRE_BUILD		"physics/metal/metal_chainlink_impact_soft3.wav"
#define SND_WIRE_REMOVE		"physics/metal/metal_grenade_impact_hard3.wav"

#define SND_WALL_BUILD		"physics/concrete/rock_scrape_rough_loop1.wav"
#define SND_WALL_REMOVE_FMT	"physics/concrete/rock_impact_hard%d.wav"	// %d = 1..6

// No sounds were specified for the .50 cal, so it reuses the metal ones.
#define SND_CAL_BUILD		"physics/metal/metal_computer_impact_hard3.wav"
#define SND_CAL_REMOVE		"physics/metal/metal_grenade_impact_hard3.wav"

// Mostly plastic, so a plastic sound leads and a quieter metal one plays on top of it.
#define SND_BARRICADE_BUILD_FMT		"physics/plastic/plastic_barrel_impact_hard%d.wav"	// %d = 1..4
#define SND_BARRICADE_BUILD_METAL	"physics/metal/metal_box_impact_soft%d.wav"			// %d = 1..3
#define SND_BARRICADE_REMOVE_FMT	"physics/plastic/plastic_barrel_break%d.wav"		// %d = 1..2
#define SND_BARRICADE_REMOVE_METAL	"physics/metal/metal_box_break1.wav"
#define SND_BARRICADE_METAL_VOL		0.4

#define SND_MARKER_HIT		"buttons/arena_switch_press_02.wav"

#define FORT_NAME		"sm_fortification"
#define GHOST_NAME		"sm_fortification_ghost"

#define TEAM_SURVIVOR	2
#define TEAM_INFECTED	3
#define ZC_TANK			8

// Fortification types
// Also the order +zoom cycles through them in build mode.
#define TYPE_WIRE		0
#define TYPE_WALL		1
#define TYPE_BARRICADE	2
#define TYPE_CAL		3
#define TYPE_MINIGUN	4
#define NUM_TYPES		5

// The wire on top of a barricade, relative to the barricade: where the model sits on the top beam, and the box
// that the wire model fills there (barricade collision bounds stop at the beam, this is what hurts).
// The model is not rotated, so the box is its vertex extents (x -18.4..10, y -45.4..46.1, z -2.1..26) moved by the position.
float g_BarricadeWirePos[3]  = { 0.0, 0.0, 143.0 };
float g_BarricadeWireMins[3] = { -18.4, -45.4, 140.9 };
float g_BarricadeWireMaxs[3] = { 10.0, 46.1, 169.0 };

// Hard cap on fortifications alive at once.
#define MAX_FORTS		128

// Rendering. Glows are drawn on top of the model for every player in range, so they don't reach across the map.
#define GLOW_RANGE			1200	// units; blueprints and holograms stop glowing past this
#define WIRE_FADE_MIN		1000	// barbed wire has a single LOD: it fades out instead of drawing every triangle far away
#define WIRE_FADE_MAX		1400

// The hologram only moves / rechecks its spot when the aim moved this much, or after PLACE_RECHECK seconds.
#define GHOST_MOVE_SQR		1.0		// squared units
#define GHOST_YAW			0.5		// degrees
#define PLACE_RECHECK		0.2

// Seconds the build counts (+walk and +use) stay up before the aim status can replace them.
#define COUNTS_SHOW_TIME	3.0

// Placement checks (see CanPlace)
#define PLACE_STEP			18.0	// height of steps / slopes / curbs the bottom of a fortification may sit in
#define PLACE_INSET			2.0		// sides are shrunk by this much so touching a wall is not intersecting it
#define PLACE_GROUND_TOL	8.0		// a footprint point counts as on the ground if the floor is this close below it
#define PLACE_GROUND_MIN	2		// footprint points (of 5: center + 4 corners) that must be on the ground
// Nav areas a fortification may not be built in: start area, saferooms, rescue closets.
#define PLACE_NAV_BLOCKED	(NAV_SPAWN_PLAYER_START | NAV_SPAWN_CHECKPOINT | NAV_SPAWN_RESCUE_CLOSET)

enum struct FortData
{
	int   ref;
	int   type;
	int   slot;				// damage-timer row if it has barbed wire, -1 if not
	int   wireRef;			// the wire model on top of a barricade, -1 if none
	int   ownerUserId;
	float yaw;
	bool  done;
	float progress;			// 0..100
	bool  glowOn;
	bool  glowNear;
	bool  hasMarker;		// crit marker belongs to the blueprint and keeps its spot
	float mpos[3];
	float mnorm[3];
	float mdir[3];
	int   alpha;
	float pos[3];
	float mins[3];
	float maxs[3];
}

char g_TypeName[NUM_TYPES][24] = { "Barbed Wire", "Bremer Wall", "Barricade", ".50 Cal", "Minigun" };
char g_TypeModel[NUM_TYPES][PLATFORM_MAX_PATH] = { MODEL_WIRE, MODEL_WALL, MODEL_BARRICADE, MODEL_CAL, MODEL_MINIGUN };

// Addon-wide convars
ConVar g_cvEnable;
ConVar g_cvMaxDist;
ConVar g_cvCooldown;
ConVar g_cvBlockMelee;
ConVar g_cvGlow;
ConVar g_cvMaxTotal;
ConVar g_cvMelee;
ConVar g_cvCritRadius;
ConVar g_cvNonCrit;
ConVar g_cvHints;
ConVar g_cvMarkerMove;

// Per fortification type
ConVar g_cvDismantleTime[NUM_TYPES];
ConVar g_cvCrits[NUM_TYPES];			// crit hits needed
ConVar g_cvCalMax;
ConVar g_cvMiniMax;
ConVar g_cvTypeEnable[NUM_TYPES];

// Barbed wire behaviour
ConVar g_cvWireDamage;
ConVar g_cvWireDamageInfected;
ConVar g_cvWireInterval;
ConVar g_cvWireSlow;
ConVar g_cvWireTankImmune;

ArrayList g_Forts;

// Cached model bounds per type
float g_TypeMins[NUM_TYPES][3];
float g_TypeMaxs[NUM_TYPES][3];
bool  g_TypeBounds[NUM_TYPES];
int   g_TypeSurf[NUM_TYPES];		// 0 = unknown, 1 = real collision surface works, 2 = no usable mesh (shrunk box)
int   g_TypeSurfMiss[NUM_TYPES];

// Per client
int   g_GhostRef[MAXPLAYERS + 1] = {-1, ...};
int   g_GhostWireRef[MAXPLAYERS + 1] = {-1, ...};	// the wire on top of a barricade hologram
int   g_GhostType[MAXPLAYERS + 1];
int   g_GhostState[MAXPLAYERS + 1];				// 0 = none, 1 = valid colour, 2 = invalid colour
float g_GhostPos[MAXPLAYERS + 1][3];			// where the hologram was last moved to
float g_GhostYaw[MAXPLAYERS + 1];
float g_PlacePos[MAXPLAYERS + 1][3];			// last CanPlace result and what it was for
float g_PlaceYaw[MAXPLAYERS + 1];
int   g_PlaceType[MAXPLAYERS + 1];
int   g_PlaceReason[MAXPLAYERS + 1];
float g_PlaceNext[MAXPLAYERS + 1];
int   g_DisRef[MAXPLAYERS + 1] = {-1, ...};		// fortification currently being dismantled
float g_DisStart[MAXPLAYERS + 1];
float g_DisEnd[MAXPLAYERS + 1];
int   g_DisPct[MAXPLAYERS + 1];
int   g_Type[MAXPLAYERS + 1];					// selected fortification type
int   g_RotState[MAXPLAYERS + 1];				// 0 = 0 degrees, 1 = 90 degrees
int   g_LastButtons[MAXPLAYERS + 1];
float g_NextAction[MAXPLAYERS + 1];
bool  g_BuildMode[MAXPLAYERS + 1];				// placement (build) mode is on
bool  g_BindsShown[MAXPLAYERS + 1];				// tool controls were printed to this player this chapter
float g_NextSwing[MAXPLAYERS + 1];
float g_MuteHitUntil[MAXPLAYERS + 1];		// melee impact sounds of this player are blocked until then
char  g_StatusText[MAXPLAYERS + 1][96];		// status line currently shown in the hint box ("" = none of ours)
bool  g_bLeft4DHooks;						// left4dhooks loaded: safe zone / spawn area placement check available
float g_StatusNext[MAXPLAYERS + 1];			// when the same status line is re-sent so it doesn't fade
float g_CountsUntil[MAXPLAYERS + 1];		// the build counts stay in the hint box until then

// Crit marker, one per player, only visible to that player
int   g_MarkerRef[MAXPLAYERS + 1] = {-1, ...};
int   g_MarkerFortRef[MAXPLAYERS + 1] = {-1, ...};
float g_MarkerNextTry[MAXPLAYERS + 1];
float g_MarkerNextDraw[MAXPLAYERS + 1];
float g_MarkerHintNext[MAXPLAYERS + 1];
int   g_BeamSprite;

// Indexed by entity index (players + common infected share these)
int   g_GhostOwner[2049];
int   g_TargetRef[2049];
bool  g_Slowed[2049];
bool  g_AnySlowed;
float g_LastPos[2049][3];
bool  g_HasLastPos[2049];
float g_LoopUntil[2049];

// Next time barbed wire [slot] may damage entity [index]. One timer per wire per target = stacking damage.
float g_SlotNextDmg[MAX_FORTS][2049];
bool  g_SlotUsed[MAX_FORTS];

// List indexes of the finished barbed wires, rebuilt every frame.
int   g_Wires[MAX_FORTS];
int   g_WireCount;

public Plugin myinfo =
{
	name        = "[L4D2] Fortifications",
	author      = "Haze_of_dream",
	description = "Build and dismantle various constructions.",
	version     = PLUGIN_VERSION,
	url         = ""
};

public void OnPluginStart()
{
	AddNormalSoundHook(OnNormalSound);

	if (GetEngineVersion() != Engine_Left4Dead2)
		SetFailState("This plugin only works on Left 4 Dead 2.");

	CreateConVar("sm_fortifications_version", PLUGIN_VERSION, "Fortifications version", FCVAR_NOTIFY | FCVAR_DONTRECORD);

	// ---- Addon-wide ----
	g_cvEnable     = CreateConVar("sm_fortifications_enable",      "1",     "Enable the plugin.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvMaxDist    = CreateConVar("sm_fortifications_distance",    "150.0", "Maximum placement/dismantle distance from your eyes (units).", FCVAR_NOTIFY, true, 16.0, true, 1000.0);
	g_cvCooldown   = CreateConVar("sm_fortifications_cooldown",    "0.01",   "Seconds between placing / starting a dismantle.", FCVAR_NOTIFY, true, 0.0);
	g_cvBlockMelee = CreateConVar("sm_fortifications_block_melee", "1",     "Consume the knife buttons used by the tool (attack while in build mode, zoom, and shove while aiming at a fortification).", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvGlow       = CreateConVar("sm_fortifications_glow",        "1",     "Hologram outline, and the glow on blueprints that are nearly finished.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvMaxTotal   = CreateConVar("sm_fortifications_max",         "6",     "Global limit of fortifications per player. Building past it destroys that player's oldest one.", FCVAR_NOTIFY, true, 1.0, true, 100.0);
	g_cvMelee      = CreateConVar("sm_fortifications_melee_range", "150.0",  "Knife reach used for swings and the furthest a crit marker may be from your eyes.", FCVAR_NOTIFY, true, 20.0, true, 300.0);
	g_cvCritRadius = CreateConVar("sm_fortifications_crit_radius", "5.0",  "How close (units) your swing must pass to the crit marker to count as a crit.", FCVAR_NOTIFY, true, 2.0, true, 100.0);
	g_cvNonCrit    = CreateConVar("sm_fortifications_noncrit_factor", "0.25", "Progress a swing that misses the marker gives, as a fraction of a crit.", FCVAR_NOTIFY, true, 0.0, true, 1.0);

	g_cvHints      = CreateConVar("sm_fortifications_hints",       "0",     "Show guidance hints (no fortification in range, crit marker help, blueprint tips). Type/mode switching and error messages always show.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvMarkerMove = CreateConVar("sm_fortifications_marker_move", "50.0",  "Furthest (units) a crit marker may jump along its line after being hit.", FCVAR_NOTIFY, true, 8.0, true, 500.0);

	// ---- Barbed wire ----
	g_cvTypeEnable[TYPE_WIRE] = CreateConVar("sm_barbedwire_enable", "1", "Allow building barbed wire.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvDismantleTime[TYPE_WIRE] = CreateConVar("sm_barbedwire_dismantle_time", "0.8",  "Seconds you must HOLD the dismantle button on a barbed wire. 0 = instant.", FCVAR_NOTIFY, true, 0.0, true, 120.0);
	g_cvCrits[TYPE_WIRE]         = CreateConVar("sm_barbedwire_crits",          "1",    "Crit marker hits needed to finish a barbed wire.", FCVAR_NOTIFY, true, 1.0, true, 50.0);
	g_cvWireDamage     = CreateConVar("sm_barbedwire_damage",     "10.0", "Damage each barbed wire deals per tick to survivors touching it.", FCVAR_NOTIFY, true, 0.0);
	g_cvWireDamageInfected = CreateConVar("sm_barbedwire_damage_infected", "40.0", "Damage each barbed wire deals per tick to non-survivors (special and common infected) touching it.", FCVAR_NOTIFY, true, 0.0);
	g_cvWireInterval   = CreateConVar("sm_barbedwire_interval",   "0.5",  "Seconds between damage ticks, tracked separately for every wire and every target.", FCVAR_NOTIFY, true, 0.05);
	g_cvWireSlow       = CreateConVar("sm_barbedwire_slow",       "0.2",  "Movement speed multiplier while touching any barbed wire (1.0 = no slow). Does not stack.", FCVAR_NOTIFY, true, 0.05, true, 1.0);
	g_cvWireTankImmune = CreateConVar("sm_barbedwire_tank_immune", "1",   "Make tanks immune to the barbed wire slowdown (they still take damage).", FCVAR_NOTIFY, true, 0.0, true, 1.0);

	// ---- Bremer wall ----
	g_cvTypeEnable[TYPE_WALL] = CreateConVar("sm_bremerwall_enable", "1", "Allow building Bremer walls.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvDismantleTime[TYPE_WALL] = CreateConVar("sm_bremerwall_dismantle_time", "6.0", "Seconds you must HOLD the dismantle button on a Bremer wall. 0 = instant.", FCVAR_NOTIFY, true, 0.0, true, 120.0);
	g_cvCrits[TYPE_WALL]         = CreateConVar("sm_bremerwall_crits",          "8",   "Crit marker hits needed to finish a Bremer wall.", FCVAR_NOTIFY, true, 1.0, true, 50.0);

	// ---- .50 cal ----
	g_cvTypeEnable[TYPE_CAL]  = CreateConVar("sm_50cal_enable",      "1", "Allow building .50 cals.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvDismantleTime[TYPE_CAL]  = CreateConVar("sm_50cal_dismantle_time", "3.0",  "Seconds you must HOLD the dismantle button on a .50 cal. 0 = instant.", FCVAR_NOTIFY, true, 0.0, true, 120.0);
	g_cvCrits[TYPE_CAL]          = CreateConVar("sm_50cal_crits",          "8",    "Crit marker hits needed to finish a .50 cal.", FCVAR_NOTIFY, true, 1.0, true, 50.0);
	g_cvCalMax                   = CreateConVar("sm_50cal_max",            "1",    "How many .50 cals each player can have at once (counts toward the global limit).", FCVAR_NOTIFY, true, 1.0, true, 20.0);

	// ---- Minigun emplacement ----
	g_cvTypeEnable[TYPE_MINIGUN] = CreateConVar("sm_minigun_enable", "1", "Allow building minigun emplacements.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvDismantleTime[TYPE_MINIGUN] = CreateConVar("sm_minigun_dismantle_time", "3.0",  "Seconds you must HOLD the dismantle button on a minigun emplacement. 0 = instant.", FCVAR_NOTIFY, true, 0.0, true, 120.0);
	g_cvCrits[TYPE_MINIGUN]         = CreateConVar("sm_minigun_crits",          "8",    "Crit marker hits needed to finish a minigun emplacement.", FCVAR_NOTIFY, true, 1.0, true, 50.0);
	g_cvMiniMax                     = CreateConVar("sm_minigun_max",            "1",    "How many minigun emplacements each player can have at once (counts toward the global limit).", FCVAR_NOTIFY, true, 1.0, true, 20.0);

	// ---- Barricade ----
	g_cvTypeEnable[TYPE_BARRICADE]    = CreateConVar("sm_barricade_enable",         "1",   "Allow building barricades.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvDismantleTime[TYPE_BARRICADE] = CreateConVar("sm_barricade_dismantle_time", "1.5", "Seconds you must HOLD the dismantle button on a barricade. 0 = instant.", FCVAR_NOTIFY, true, 0.0, true, 120.0);
	g_cvCrits[TYPE_BARRICADE]         = CreateConVar("sm_barricade_crits",          "4",   "Crit marker hits needed to finish a barricade.", FCVAR_NOTIFY, true, 1.0, true, 50.0);

	AutoExecConfig(true, "fortifications");

	RegConsoleCmd("sm_fortifications", Cmd_GiveKnife, "Give yourself the knife used to build fortifications.");
	RegAdminCmd("sm_clearfortifications", Cmd_ClearForts, ADMFLAG_SLAY, "Remove all fortifications.");

	HookEvent("round_start",  Event_RoundStart, EventHookMode_PostNoCopy);
	HookEvent("round_end",    Event_RoundEnd,   EventHookMode_PostNoCopy);
	HookEvent("player_death", Event_PlayerDeath);
	HookEvent("weapon_fire",  Event_WeaponFire);

	g_Forts = new ArrayList(sizeof(FortData));
}

public void OnAllPluginsLoaded()
{
	g_bLeft4DHooks = LibraryExists("left4dhooks");
	if (!g_bLeft4DHooks)
		LogError("left4dhooks is not loaded: fortifications can be built in safe zones and spawn areas.");
}

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, "left4dhooks"))
		g_bLeft4DHooks = true;
}

public void OnLibraryRemoved(const char[] name)
{
	if (StrEqual(name, "left4dhooks"))
		g_bLeft4DHooks = false;
}

public void OnMapStart()
{
	for (int i = 1; i <= MaxClients; i++)
		g_BindsShown[i] = false;

	for (int t = 0; t < NUM_TYPES; t++)
		PrecacheModel(g_TypeModel[t], true);

	g_BeamSprite = PrecacheModel(BEAM_MATERIAL, true);

	PrecacheSound(SND_WIRE_DAMAGE, true);
	PrecacheSound(SND_WIRE_BUILD,  true);
	PrecacheSound(SND_WIRE_REMOVE, true);
	PrecacheSound(SND_WALL_BUILD,  true);
	PrecacheSound(SND_CAL_BUILD,   true);
	PrecacheSound(SND_CAL_REMOVE,  true);
	PrecacheSound(SND_MARKER_HIT,  true);
	PrecacheSound(SND_BARRICADE_REMOVE_METAL, true);

	char buf[PLATFORM_MAX_PATH];
	for (int i = 1; i <= 4; i++)
	{
		Format(buf, sizeof(buf), SND_BARRICADE_BUILD_FMT, i);
		PrecacheSound(buf, true);
	}
	for (int i = 1; i <= 3; i++)
	{
		Format(buf, sizeof(buf), SND_BARRICADE_BUILD_METAL, i);
		PrecacheSound(buf, true);
	}
	for (int i = 1; i <= 2; i++)
	{
		Format(buf, sizeof(buf), SND_BARRICADE_REMOVE_FMT, i);
		PrecacheSound(buf, true);
	}
	for (int i = 1; i <= 6; i++)
	{
		Format(buf, sizeof(buf), SND_WALL_REMOVE_FMT, i);
		PrecacheSound(buf, true);
	}

	// Make sure the CSS knife melee weapon is usable on every map.
	PrecacheModel(TOOL_V_MODEL, true);
	PrecacheModel(TOOL_W_MODEL, true);
	PrecacheGeneric(TOOL_SCRIPT, true);

	for (int t = 0; t < NUM_TYPES; t++)
	{
		g_TypeBounds[t]   = false;
		g_TypeSurf[t]     = TypeHasCollision(t) ? 0 : 2;
		g_TypeSurfMiss[t] = 0;
	}

	ResetAll();
}

public void OnMapEnd()
{
	ResetAll();
}

public void OnPluginEnd()
{
	for (int i = 1; i <= MaxClients; i++)
	{
		RemoveGhost(i);
	}

	ResetAllSlows();
	ClearAllForts();
}

public void OnClientDisconnect(int client)
{
	RemoveGhost(client);
	g_DisRef[client]      = -1;
	g_Slowed[client]      = false;
	g_TargetRef[client]   = 0;
	g_LastButtons[client] = 0;
	g_NextAction[client]  = 0.0;
	g_NextSwing[client]   = 0.0;
	g_MuteHitUntil[client] = 0.0;
	g_StatusText[client][0] = '\0';
	g_StatusNext[client]  = 0.0;
	g_RotState[client]    = 0;
	g_Type[client]        = TYPE_WIRE;
	g_BuildMode[client]   = false;
	g_BindsShown[client]  = false;
}

void ResetAll()
{
	ResetAllSlows();
	if (g_Forts != null)
		g_Forts.Clear();
	g_AnySlowed = false;

	for (int s = 0; s < MAX_FORTS; s++)
		g_SlotUsed[s] = false;

	for (int i = 0; i <= 2048; i++)
	{
		g_GhostOwner[i] = 0;
		g_TargetRef[i]  = 0;
		g_Slowed[i]     = false;
		g_HasLastPos[i] = false;
		g_LoopUntil[i]  = 0.0;
	}
	for (int i = 1; i <= MaxClients; i++)
	{
		g_GhostRef[i]       = -1;
		g_GhostWireRef[i]   = -1;
		g_DisRef[i]         = -1;
		g_MarkerRef[i]      = -1;
		g_MarkerFortRef[i]  = -1;
		g_GhostState[i]     = 0;

		// Game time restarts with each map: anything left from the last one would look far in the future.
		g_NextAction[i]     = 0.0;
		g_NextSwing[i]      = 0.0;
		g_MuteHitUntil[i]   = 0.0;
		g_StatusNext[i]     = 0.0;
		g_MarkerNextTry[i]  = 0.0;
		g_MarkerNextDraw[i] = 0.0;
		g_MarkerHintNext[i] = 0.0;
		g_PlaceNext[i]      = 0.0;
		g_CountsUntil[i]    = 0.0;
	}
}

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	ClearAllForts();
	ResetAll();
}

public void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		RemoveGhost(i);
	}

	ResetAllSlows();
	ClearAllForts();
}

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client > 0)
	{
		RemoveGhost(client);
		g_BuildMode[client] = false;
		ResetSlow(client);
	}
}

// Every real melee swing (including held auto-swings) counts, aimed wherever the crosshair is
// at the moment the swing starts.
public void Event_WeaponFire(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_cvEnable.BoolValue)
		return;

	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client < 1 || !CanUseTool(client) || g_BuildMode[client] || IsDismantling(client))
		return;

	char weapon[32];
	event.GetString("weapon", weapon, sizeof(weapon));
	if (StrContains(weapon, "melee", false) == -1 && !StrEqual(weapon, TOOL_MELEE, false))
		return;

	// Guards against the event firing twice for the same swing.
	float now = GetGameTime();
	if (now < g_NextSwing[client])
		return;
	g_NextSwing[client] = now + 0.1;

	float eye[3], ang[3], fwd[3];
	GetClientEyePosition(client, eye);
	GetClientEyeAngles(client, ang);
	GetAngleVectors(ang, fwd, NULL_VECTOR, NULL_VECTOR);

	// Swinging at a fortification: its own construction sound plays, the melee impact sound is clutter.
	if (FindFortAimedAt(eye, fwd, g_cvMelee.FloatValue) != -1)
		g_MuteHitUntil[client] = now + MUTE_HIT_TIME;

	HandleSwing(client, eye, fwd);
}

/*
 * Blocks melee impact sounds that come from a fortification, or from a player (or their weapon) shortly after
 * they swung at one. This plugin's own sounds are never blocked.
 * Note: the swinging player may still hear their own hit if their client plays it locally (prediction).
 */
public Action OnNormalSound(int clients[MAXPLAYERS], int &numClients, char sample[PLATFORM_MAX_PATH], int &entity, int &channel, float &volume, int &level, int &pitch, int &flags, char soundEntry[PLATFORM_MAX_PATH], int &seed)
{
	if (entity <= 0 || !IsValidEntity(entity))
		return Plugin_Continue;

	// Weapon / physics impacts only, never voices or pain sounds.
	if (StrContains(sample, "impact", false) == -1 && StrContains(sample, "hit", false) == -1)
		return Plugin_Continue;
	if (StrContains(sample, "weapons/", false) == -1 && StrContains(sample, "physics/", false) == -1)
		return Plugin_Continue;

	if (IsOwnSound(sample))
		return Plugin_Continue;

	int client = entity;
	if (client > MaxClients && HasEntProp(entity, Prop_Send, "m_hOwnerEntity"))
		client = GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity");

	if (client >= 1 && client <= MaxClients)
	{
		if (GetGameTime() < g_MuteHitUntil[client])
			return Plugin_Stop;
		return Plugin_Continue;
	}

	if (FindFortByRef(EntIndexToEntRef(entity)) != -1)
		return Plugin_Stop;

	return Plugin_Continue;
}

bool IsOwnSound(const char[] sample)
{
	return StrContains(sample, SND_WIRE_DAMAGE, false) != -1
		|| StrContains(sample, SND_WIRE_BUILD, false) != -1
		|| StrContains(sample, SND_WIRE_REMOVE, false) != -1
		|| StrContains(sample, "rock_impact_hard", false) != -1	// SND_WALL_REMOVE_FMT
		|| StrContains(sample, SND_WALL_BUILD, false) != -1
		|| StrContains(sample, SND_CAL_BUILD, false) != -1
		|| StrContains(sample, "plastic_barrel_impact_hard", false) != -1	// SND_BARRICADE_BUILD_FMT
		|| StrContains(sample, "metal_box_impact_soft", false) != -1		// SND_BARRICADE_BUILD_METAL
		|| StrContains(sample, SND_MARKER_HIT, false) != -1;
}

/* ------------------------------------------------------------------ */
/*  Commands                                                          */
/* ------------------------------------------------------------------ */

public Action Cmd_GiveKnife(int client, int args)
{
	if (client == 0)
	{
		ReplyToCommand(client, "[Fortifications] This command can only be used in game.");
		return Plugin_Handled;
	}

	if (!IsClientInGame(client) || !IsPlayerAlive(client) || GetClientTeam(client) != TEAM_SURVIVOR)
	{
		ReplyToCommand(client, "[Fortifications] You must be an alive survivor.");
		return Plugin_Handled;
	}

	// L4D2 melee weapons use weapon_melee. "give knife" asks GiveNamedItem for
	// the nonexistent weapon_knife classname and causes the NULL Ent error.
	int knife = CreateEntityByName("weapon_melee");
	if (knife == -1 || !IsValidEntity(knife))
	{
		PrintToChat(client, "[Fortifications] Failed to create weapon_melee.");
		return Plugin_Handled;
	}
	DispatchKeyValue(knife, "melee_script_name", TOOL_MELEE);
	DispatchSpawn(knife);
	if (!IsValidEntity(knife))
	{
		PrintToChat(client, "[Fortifications] Failed to spawn the knife melee weapon.");
		return Plugin_Handled;
	}

	char scriptName[32];
	GetEntPropString(knife, Prop_Data, "m_strMapSetScriptName", scriptName, sizeof(scriptName));
	if (!StrEqual(scriptName, TOOL_MELEE, false))
	{
		AcceptEntityInput(knife, "Kill");
		PrintToChat(client, "[Fortifications] The knife melee script is unavailable on this server/map.");
		return Plugin_Handled;
	}

	float origin[3];
	GetClientAbsOrigin(client, origin);
	origin[2] += 8.0;
	TeleportEntity(knife, origin, NULL_VECTOR, NULL_VECTOR);

	// Only replace the existing secondary once the new knife is validated.
	int oldWeapon = GetPlayerWeaponSlot(client, 1);
	if (oldWeapon > MaxClients && IsValidEntity(oldWeapon))
	{
		RemovePlayerItem(client, oldWeapon);
		AcceptEntityInput(oldWeapon, "Kill");
	}
	EquipPlayerWeapon(client, knife);
	FakeClientCommand(client, "use weapon_melee");

	PrintToolBinds(client);
	return Plugin_Handled;
}

void PrintToolBinds(int client)
{
	g_BindsShown[client] = true;

	PrintToChat(client, "\x04[Fortifications]\x01 Construction tool controls:");
	PrintToChat(client, "\x05Hold Walk + press Zoom\x01 = toggle build mode");
	PrintToChat(client, "\x04In build mode:\x01 \x05Attack\x01 = place blueprint, \x05Zoom\x01 = change type, \x05Reload\x01 = rotate");
	PrintToChat(client, "\x04Out of build mode:\x01 \x05Attack\x01 = swing at a blueprint to build it, hit the crit marker for big progress");
	PrintToChat(client, "\x05Hold Shove\x01 = dismantle, \x05Walk + Use\x01 = show your build counts");
}

public Action Cmd_ClearForts(int client, int args)
{
	ClearAllForts();
	ReplyToCommand(client, "[Fortifications] All fortifications removed.");
	return Plugin_Handled;
}

void ClearAllForts()
{
	if (g_Forts == null)
		return;

	for (int i = g_Forts.Length - 1; i >= 0; i--)
	{
		FortData w;
		g_Forts.GetArray(i, w);
		int ent = EntRefToEntIndex(w.ref);
		if (ent != INVALID_ENT_REFERENCE)
		{
			StopBuildSound(ent, w.type);
			AcceptEntityInput(ent, "KillHierarchy");
		}
	}
	g_Forts.Clear();

	for (int s = 0; s < MAX_FORTS; s++)
		g_SlotUsed[s] = false;
	for (int i = 1; i <= MaxClients; i++)
		g_DisRef[i] = -1;
}

/* ------------------------------------------------------------------ */
/*  Fortification list helpers                                        */
/* ------------------------------------------------------------------ */

int AllocSlot()
{
	for (int s = 0; s < MAX_FORTS; s++)
	{
		if (!g_SlotUsed[s])
		{
			g_SlotUsed[s] = true;
			for (int e = 0; e <= 2048; e++)
				g_SlotNextDmg[s][e] = 0.0;
			return s;
		}
	}
	return -1;
}

// Removes an entry from the list and frees its damage-timer slot (barbed wire only).
void EraseFort(int index)
{
	FortData w;
	g_Forts.GetArray(index, w);
	if (w.slot >= 0 && w.slot < MAX_FORTS)
		g_SlotUsed[w.slot] = false;
	g_Forts.Erase(index);
}

int FindFortByRef(int ref)
{
	for (int i = 0; i < g_Forts.Length; i++)
	{
		FortData w;
		g_Forts.GetArray(i, w);
		if (w.ref == ref)
			return i;
	}
	return -1;
}

// All fortifications this player owns (finished or not).
int CountOwnedAll(int userid)
{
	int count = 0;
	for (int i = 0; i < g_Forts.Length; i++)
	{
		FortData w;
		g_Forts.GetArray(i, w);
		if (w.ownerUserId == userid && EntRefToEntIndex(w.ref) != INVALID_ENT_REFERENCE)
			count++;
	}
	return count;
}

int CountOwnedType(int userid, int type)
{
	int count = 0;
	for (int i = 0; i < g_Forts.Length; i++)
	{
		FortData w;
		g_Forts.GetArray(i, w);
		if (w.type == type && w.ownerUserId == userid && EntRefToEntIndex(w.ref) != INVALID_ENT_REFERENCE)
			count++;
	}
	return count;
}

// Destroys the player's oldest fortification (the list is in creation order).
bool DestroyOldest(int userid)
{
	for (int i = 0; i < g_Forts.Length; i++)
	{
		FortData w;
		g_Forts.GetArray(i, w);
		if (w.ownerUserId != userid)
			continue;

		int ent = EntRefToEntIndex(w.ref);
		if (ent == INVALID_ENT_REFERENCE)
			continue;

		EmitDismantleSound(w.type, w.pos);
		StopBuildSound(ent, w.type);
		AcceptEntityInput(ent, "KillHierarchy");
		EraseFort(i);
		return true;
	}
	return false;
}

// Guidance hints are off unless sm_fortifications_hints is 1.
void Hint(int client, const char[] fmt, any ...)
{
	if (!g_cvHints.BoolValue || client < 1 || client > MaxClients || !IsClientInGame(client))
		return;

	char buf[192];
	VFormat(buf, sizeof(buf), fmt, 3);
	PrintHint(client, "%s", buf);
}

// One-off messages. They replace the status line, which then must not wipe them.
void PrintHint(int client, const char[] fmt, any ...)
{
	char buf[192];
	VFormat(buf, sizeof(buf), fmt, 3);
	SendHint(client, buf);
	g_StatusText[client][0] = '\0';
}

// The client's hint box treats '%' as the start of a localization token and drops a lone one,
// so it has to be sent doubled to show up.
void SendHint(int client, const char[] text)
{
	char buf[256];
	strcopy(buf, sizeof(buf), text);
	ReplaceString(buf, sizeof(buf), "%", "%%");
	PrintHintText(client, "%s", buf);
}

/*
 * Dismantle progress and the build progress of what the player is aiming at. Shown in the hint box, which
 * uses a larger font than center text. Only re-sent when it changes, or once a second so it doesn't fade.
 */
void ShowStatus(int client, const char[] fmt, any ...)
{
	char buf[96];
	VFormat(buf, sizeof(buf), fmt, 3);

	float now = GetGameTime();
	if (StrEqual(buf, g_StatusText[client]) && now < g_StatusNext[client])
		return;

	strcopy(g_StatusText[client], sizeof(g_StatusText[]), buf);
	g_StatusNext[client] = now + 1.0;
	SendHint(client, buf);
}

// Stops refreshing the status line so it fades out by itself. Sending a blank hint would leave an empty
// hint box on screen until it times out.
void ClearStatus(int client)
{
	g_StatusText[client][0] = '\0';
}

// The player's fortifications against their limits. Types without a limit of their own only show a count.
void ShowBuildCounts(int client)
{
	int userid = GetClientUserId(client);

	char list[128], part[32];
	for (int t = 0; t < NUM_TYPES; t++)
	{
		if (!TypeEnabled(t))
			continue;

		if (t == TYPE_CAL || t == TYPE_MINIGUN)
			FormatEx(part, sizeof(part), "%s: %d/%d", g_TypeName[t], CountOwnedType(userid, t), (t == TYPE_CAL) ? g_cvCalMax.IntValue : g_cvMiniMax.IntValue);
		else
			FormatEx(part, sizeof(part), "%s: %d", g_TypeName[t], CountOwnedType(userid, t));

		if (list[0] != '\0')
			StrCat(list, sizeof(list), "  |  ");
		StrCat(list, sizeof(list), part);
	}

	PrintHint(client, "Fortifications: %d/%d\n%s", CountOwnedAll(userid), g_cvMaxTotal.IntValue, list);
	g_CountsUntil[client] = GetGameTime() + COUNTS_SHOW_TIME;
}

// Build progress of the unfinished fortification the player is aiming at (idx from FindFortAimedAt).
void ShowAimStatus(int client, int idx)
{
	// The build counts were just asked for, don't replace them.
	if (GetGameTime() < g_CountsUntil[client])
		return;

	if (idx == -1)
	{
		ClearStatus(client);
		return;
	}

	FortData w;
	g_Forts.GetArray(idx, w);

	if (w.done)
	{
		ClearStatus(client);
		return;
	}

	ShowStatus(client, "%s - %d%%", g_TypeName[w.type], RoundToFloor(FortBuiltFraction(w) * 100.0));
}

bool TypeEnabled(int type)
{
	return g_cvTypeEnable[type].BoolValue;
}

// Next enabled type after 'cur' (wraps; may return cur itself), or -1 if every type is disabled.
int NextEnabledType(int cur)
{
	for (int i = 1; i <= NUM_TYPES; i++)
	{
		int t = (cur + i) % NUM_TYPES;
		if (TypeEnabled(t))
			return t;
	}
	return -1;
}

float ClampF(float v, float lo, float hi)
{
	if (v < lo) return lo;
	if (v > hi) return hi;
	return v;
}

/* ------------------------------------------------------------------ */
/*  Model bounds                                                      */
/* ------------------------------------------------------------------ */

void FallbackBounds(int type, float mins[3], float maxs[3])
{
	switch (type)
	{
		case TYPE_WALL:
		{
			mins[0] = -48.0; mins[1] = -12.0; mins[2] = 0.0;
			maxs[0] =  48.0; maxs[1] =  12.0; maxs[2] = 80.0;
		}
		case TYPE_CAL, TYPE_MINIGUN:
		{
			mins[0] = -16.0; mins[1] = -16.0; mins[2] = 0.0;
			maxs[0] =  16.0; maxs[1] =  16.0; maxs[2] = 48.0;
		}
		case TYPE_BARRICADE:
		{
			mins[0] = -42.0; mins[1] = -48.0; mins[2] = 0.0;
			maxs[0] =  22.0; maxs[1] =  48.0; maxs[2] = 144.0;
		}
		default:
		{
			mins[0] = -64.0; mins[1] = -16.0; mins[2] = 0.0;
			maxs[0] =  64.0; maxs[1] =  16.0; maxs[2] = 56.0;
		}
	}
}

// Reads an entity's collision bounds (falls back to a per-type box) and caches them for the type.
void ReadBounds(int ent, int type, float mins[3], float maxs[3])
{
	GetEntPropVector(ent, Prop_Send, "m_vecMins", mins);
	GetEntPropVector(ent, Prop_Send, "m_vecMaxs", maxs);

	if ((maxs[0] - mins[0]) < 1.0 && (maxs[1] - mins[1]) < 1.0)
		FallbackBounds(type, mins, maxs);

	if (!g_TypeBounds[type])
	{
		for (int i = 0; i < 3; i++)
		{
			g_TypeMins[type][i] = mins[i];
			g_TypeMaxs[type][i] = maxs[i];
		}
		g_TypeBounds[type] = true;
	}
}

void GetTypeBounds(int type, float mins[3], float maxs[3])
{
	if (g_TypeBounds[type])
	{
		for (int i = 0; i < 3; i++)
		{
			mins[i] = g_TypeMins[type][i];
			maxs[i] = g_TypeMaxs[type][i];
		}
		return;
	}
	FallbackBounds(type, mins, maxs);
}

/* ------------------------------------------------------------------ */
/*  Sounds                                                            */
/* ------------------------------------------------------------------ */

void GetBuildSample(int type, char[] buf, int len)
{
	switch (type)
	{
		case TYPE_WALL: strcopy(buf, len, SND_WALL_BUILD);
		case TYPE_CAL, TYPE_MINIGUN: strcopy(buf, len, SND_CAL_BUILD);
		case TYPE_BARRICADE: Format(buf, len, SND_BARRICADE_BUILD_FMT, GetRandomInt(1, 4));
		default:        strcopy(buf, len, SND_WIRE_BUILD);
	}
}

// Build sounds use their own static channel so they can be stopped cleanly (the wall one loops).
void EmitBuildSound(int ent, int type)
{
	char snd[PLATFORM_MAX_PATH];
	GetBuildSample(type, snd, sizeof(snd));
	EmitSoundToAll(snd, ent, SNDCHAN_STATIC, SNDLEVEL_NORMAL);
}

void StopBuildSound(int ent, int type)
{
	if (ent <= MaxClients || !IsValidEntity(ent))
		return;

	char snd[PLATFORM_MAX_PATH];
	GetBuildSample(type, snd, sizeof(snd));
	StopSound(ent, SNDCHAN_STATIC, snd);
}

// The construction sound for one swing. The looping wall sound is cut off shortly after each hit.
void PlayConstructionHit(int ent, int type)
{
	StopBuildSound(ent, type);
	EmitBuildSound(ent, type);

	if (type == TYPE_WALL)
	{
		g_LoopUntil[ent] = GetGameTime() + 0.9;
		CreateTimer(0.95, Timer_StopWallLoop, EntIndexToEntRef(ent), TIMER_FLAG_NO_MAPCHANGE);
	}
	else if (type == TYPE_BARRICADE)
	{
		char snd[PLATFORM_MAX_PATH];
		Format(snd, sizeof(snd), SND_BARRICADE_BUILD_METAL, GetRandomInt(1, 3));
		EmitSoundToAll(snd, ent, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, SND_BARRICADE_METAL_VOL);
	}
}

public Action Timer_StopWallLoop(Handle timer, any ref)
{
	int ent = EntRefToEntIndex(ref);
	if (ent != INVALID_ENT_REFERENCE && GetGameTime() >= g_LoopUntil[ent] - 0.01)
		StopBuildSound(ent, TYPE_WALL);
	return Plugin_Stop;
}

void EmitDismantleSound(int type, const float pos[3])
{
	char snd[PLATFORM_MAX_PATH];
	switch (type)
	{
		case TYPE_WALL: Format(snd, sizeof(snd), SND_WALL_REMOVE_FMT, GetRandomInt(1, 6));
		case TYPE_CAL, TYPE_MINIGUN: strcopy(snd, sizeof(snd), SND_CAL_REMOVE);
		case TYPE_BARRICADE: Format(snd, sizeof(snd), SND_BARRICADE_REMOVE_FMT, GetRandomInt(1, 2));
		default:        strcopy(snd, sizeof(snd), SND_WIRE_REMOVE);
	}

	// Emit from the world position, because the entity is about to be killed.
	EmitSoundToAll(snd, SOUND_FROM_WORLD, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, SNDVOL_NORMAL, SNDPITCH_NORMAL, -1, pos);

	if (type == TYPE_BARRICADE)
		EmitSoundToAll(SND_BARRICADE_REMOVE_METAL, SOUND_FROM_WORLD, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, SND_BARRICADE_METAL_VOL, SNDPITCH_NORMAL, -1, pos);
}

/* ------------------------------------------------------------------ */
/*  Input handling                                                    */
/* ------------------------------------------------------------------ */

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
	int prev = g_LastButtons[client];
	g_LastButtons[client] = buttons;
	int pressed = buttons & ~prev;
	int held    = buttons;

	if (!g_cvEnable.BoolValue || !CanUseTool(client))
	{
		RemoveGhost(client);
		CancelDismantle(client, false);
		g_BuildMode[client] = false;
		return Plugin_Continue;
	}

	if (!g_BindsShown[client])
		PrintToolBinds(client);

	return RunCmdTool(client, buttons, pressed, held);
}

/* ---- Place blueprints, build with swings / crit markers ---------- */

Action RunCmdTool(int client, int &buttons, int pressed, int held)
{
	float now        = GetGameTime();
	bool  walkHeld   = ((held & (IN_WALK | IN_SPEED)) != 0);
	bool  dismantling = IsDismantling(client);

	// +walk and +use together: show how many fortifications this player has.
	if (walkHeld && (held & IN_USE) && (pressed & (IN_USE | IN_WALK | IN_SPEED)))
		ShowBuildCounts(client);

	// Hold +walk and press +zoom: toggle build mode. In build mode +zoom alone cycles the type.
	if ((pressed & IN_ZOOM) && !dismantling)
	{
		if (walkHeld)
		{
			g_BuildMode[client] = !g_BuildMode[client];
			RemoveGhost(client);
		}
		else if (g_BuildMode[client])
		{
			int nt = NextEnabledType(g_Type[client]);
			if (nt == -1)
			{
				PrintHint(client, "Every fortification type is disabled.");
			}
			else
			{
				g_Type[client] = nt;
				RemoveGhost(client);
				PrintHint(client, "%s", g_TypeName[nt], g_cvCrits[nt].IntValue, (g_cvCrits[nt].IntValue == 1) ? "" : "s");
			}
		}
	}

	// RELOAD toggles between exactly two rotations: 0 and 90 degrees (build mode only).
	if (g_BuildMode[client] && !dismantling && (pressed & IN_RELOAD))
		g_RotState[client] = (g_RotState[client] == 0) ? 1 : 0;

	if (!TypeEnabled(g_Type[client]))
	{
		int nt = NextEnabledType(g_Type[client]);
		if (nt != -1)
		{
			g_Type[client] = nt;
			RemoveGhost(client);
		}
	}
	int type = g_Type[client];

	float eye[3], fwd[3], pos[3], ang[3], dist;
	ComputePlacement(client, eye, fwd, dist, pos, ang);

	int   userid = GetClientUserId(client);
	int   aimIdx = FindFortAimedAt(eye, fwd, dist);

	// +attack2 (shove) held: dismantle. Works in and out of build mode.
	if (dismantling)
	{
		RemoveGhost(client);
		TickDismantle(client, eye, fwd, dist, held, IN_ATTACK2, now);
	}
	else if ((pressed & IN_ATTACK2) && aimIdx != -1 && now >= g_NextAction[client])
	{
		g_NextAction[client] = now + g_cvCooldown.FloatValue;
		BeginDismantleIdx(client, aimIdx);
		dismantling = IsDismantling(client);
	}

	if (!dismantling)
	{
		if (g_BuildMode[client])
		{
			// Placement: the hologram follows the crosshair, MOUSE1 drops a blueprint.
			bool place  = (pressed & IN_ATTACK) && now >= g_NextAction[client];
			int  reason = CanPlaceCached(client, userid, type, pos, ang[1], place);
			bool valid  = (reason == 0);

			UpdateGhost(client, type, pos, ang, valid);

			if (place)
			{
				g_NextAction[client] = now + g_cvCooldown.FloatValue;
				if (valid)
					PlaceBlueprint(client, userid, type, pos, ang);
				else
					PrintPlaceFailure(client, type, reason);
			}
		}
		else
		{
			// Normal attacking: swings that connect with a blueprint build it (see Event_WeaponFire).
			RemoveGhost(client);
			UpdateMarker(client, eye, fwd);
		}
	}

	if (!dismantling)
	{
		// An instant dismantle or a placement past the limit may have just erased a fortification: aimIdx is stale.
		ShowAimStatus(client, (pressed & (IN_ATTACK | IN_ATTACK2)) ? FindFortAimedAt(eye, fwd, dist) : aimIdx);
	}

	// Consume the tool's buttons. Attacking stays allowed outside build mode.
	bool changed = false;
	if (g_cvBlockMelee.BoolValue)
	{
		int strip = IN_ZOOM;
		if (g_BuildMode[client])
			strip |= IN_ATTACK;
		if (dismantling || aimIdx != -1)
			strip |= IN_ATTACK2;

		if (buttons & strip)
		{
			buttons &= ~strip;
			changed = true;
		}
	}

	return changed ? Plugin_Changed : Plugin_Continue;
}

void PrintPlaceFailure(int client, int type, int reason)
{
	switch (reason)
	{
		case 1: PrintHint(client, "You can only have %d %s at a time.", (type == TYPE_MINIGUN) ? g_cvMiniMax.IntValue : g_cvCalMax.IntValue, g_TypeName[type]);
		case 2: PrintHint(client, "Too many fortifications on the map right now.");
		case 3: PrintHint(client, "Something is standing in the way.");
		case 4: PrintHint(client, "%s is disabled on this server.", g_TypeName[type]);
		case 5: PrintHint(client, "You can't build in a safe zone or spawn area.");
		case 6: PrintHint(client, "Fortifications need solid ground to stand on.");
		case 7: PrintHint(client, "That would go through a wall.");
	}
}

bool CanUseTool(int client)
{
	if (!IsClientInGame(client) || IsFakeClient(client) || !IsPlayerAlive(client))
		return false;
	if (GetClientTeam(client) != TEAM_SURVIVOR)
		return false;
	if (GetEntProp(client, Prop_Send, "m_isIncapacitated") != 0)
		return false;

	return IsHoldingTool(client);
}

bool IsHoldingTool(int client)
{
	int wep = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	if (wep <= MaxClients || !IsValidEntity(wep))
		return false;

	char buf[64];
	GetEdictClassname(wep, buf, sizeof(buf));
	if (!StrEqual(buf, "weapon_melee"))
		return false;

	GetEntPropString(wep, Prop_Data, "m_strMapSetScriptName", buf, sizeof(buf));
	return StrEqual(buf, TOOL_MELEE, false);
}

void ComputePlacement(int client, float eye[3], float fwd[3], float &dist, float pos[3], float ang[3])
{
	float eyeAng[3], end[3];
	GetClientEyePosition(client, eye);
	GetClientEyeAngles(client, eyeAng);
	GetAngleVectors(eyeAng, fwd, NULL_VECTOR, NULL_VECTOR);

	float maxDist = g_cvMaxDist.FloatValue;
	for (int i = 0; i < 3; i++)
		end[i] = eye[i] + fwd[i] * maxDist;

	TR_TraceRayFilter(eye, end, MASK_SOLID, RayType_EndPoint, TraceFilter, client);

	dist = maxDist;
	if (TR_DidHit())
	{
		float normal[3];
		TR_GetEndPosition(pos);
		TR_GetPlaneNormal(INVALID_HANDLE, normal);
		dist = GetVectorDistance(eye, pos);
		for (int i = 0; i < 3; i++)
			pos[i] += normal[i] * 2.0;
	}
	else
	{
		for (int i = 0; i < 3; i++)
			pos[i] = end[i];
	}

	// Drop the fortification onto the floor beneath the crosshair point.
	float from[3], to[3], ground[3];
	for (int i = 0; i < 3; i++)
	{
		from[i] = pos[i];
		to[i]   = pos[i];
	}
	from[2] += 8.0;
	to[2]   -= 64.0;

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
	if (entity >= 1 && entity <= MaxClients)
		return false;

	if (entity > MaxClients && IsValidEntity(entity))
	{
		char name[48];
		GetEntPropString(entity, Prop_Data, "m_iName", name, sizeof(name));
		if (strncmp(name, FORT_NAME, strlen(FORT_NAME)) == 0)
			return false;
	}
	return true;
}

/**
 * Whether a fortification of this type may be placed here.
 * 0 = ok, 1 = .50 cal / minigun limit, 2 = global cap on the map, 3 = blocked by a player (solid types only), 4 = type disabled,
 * 5 = safe zone / spawn area, 6 = not on the ground, 7 = intersects the world
 * (The per-player limit is not a failure: building past it destroys the player's oldest fortification.)
 */
int CanPlace(int userid, int type, const float pos[3], float yaw)
{
	if (!TypeEnabled(type))
		return 4;

	float mins[3], maxs[3];
	GetTypeBounds(type, mins, maxs);

	// The wire on top needs headroom as well.
	if (type == TYPE_BARRICADE)
		maxs[2] = g_BarricadeWireMaxs[2];

	if (InBlockedZone(pos, yaw, mins, maxs))
		return 5;

	if (!OnGround(pos, yaw, mins, maxs))
		return 6;

	if (HitsWorld(pos, yaw, mins, maxs))
		return 7;

	if (type == TYPE_CAL && CountOwnedType(userid, TYPE_CAL) >= g_cvCalMax.IntValue)
		return 1;

	if (type == TYPE_MINIGUN && CountOwnedType(userid, TYPE_MINIGUN) >= g_cvMiniMax.IntValue)
		return 1;

	if (g_Forts.Length >= MAX_FORTS)
		return 2;

	if (type != TYPE_WIRE && PlayersOverlap(pos, yaw, mins, maxs))
		return 3;

	return 0;
}

// Footprint sample points at the base: [0] = center, [1..4] = corners (inset by PLACE_INSET).
void FootprintPoints(const float pos[3], float yaw, const float mins[3], const float maxs[3], float pts[5][3])
{
	float lo0 = mins[0] + PLACE_INSET, hi0 = maxs[0] - PLACE_INSET;
	float lo1 = mins[1] + PLACE_INSET, hi1 = maxs[1] - PLACE_INSET;

	float local[5][3];
	local[0][0] = (lo0 + hi0) * 0.5; local[0][1] = (lo1 + hi1) * 0.5;
	local[1][0] = lo0; local[1][1] = lo1;
	local[2][0] = hi0; local[2][1] = lo1;
	local[3][0] = hi0; local[3][1] = hi1;
	local[4][0] = lo0; local[4][1] = hi1;

	for (int i = 0; i < 5; i++)
	{
		local[i][2] = mins[2];
		LocalToWorld(pos, yaw, local[i], pts[i]);
	}
}

// Any part of the footprint in the start area, a saferoom or a rescue closet (needs left4dhooks).
bool InBlockedZone(const float pos[3], float yaw, const float mins[3], const float maxs[3])
{
	if (!g_bLeft4DHooks)
		return false;

	float pts[5][3];
	FootprintPoints(pos, yaw, mins, maxs, pts);

	for (int i = 0; i < 5; i++)
	{
		float pt[3];
		pt = pts[i];
		pt[2] += 1.0;

		if (L4D_IsPositionInFirstCheckpoint(pt) || L4D_IsPositionInLastCheckpoint(pt))
			return true;

		Address area = L4D_GetNearestNavArea(pt, 120.0, false, false, false, TEAM_SURVIVOR);
		if (area != Address_Null && (L4D_GetNavArea_SpawnAttributes(area) & PLACE_NAV_BLOCKED))
			return true;
	}
	return false;
}

// At least PLACE_GROUND_MIN footprint points have walkable floor just below them: nothing is built in mid air.
bool OnGround(const float pos[3], float yaw, const float mins[3], const float maxs[3])
{
	float pts[5][3];
	FootprintPoints(pos, yaw, mins, maxs, pts);

	int contact = 0;
	for (int i = 0; i < 5; i++)
	{
		float from[3], to[3];
		from = pts[i];
		to   = pts[i];
		from[2] += PLACE_STEP;
		to[2]   -= PLACE_GROUND_TOL;

		TR_TraceRayFilter(from, to, MASK_SOLID, RayType_EndPoint, WorldFilter);
		if (!TR_DidHit() || TR_StartSolid())
			continue;

		float normal[3];
		TR_GetPlaneNormal(INVALID_HANDLE, normal);
		if (normal[2] >= 0.7)
			contact++;
	}
	return contact >= PLACE_GROUND_MIN;
}

/**
 * Does the (yaw-rotated) box pass through world geometry? The bottom PLACE_STEP units are left out so it may sit
 * on stairs, slopes and curbs, and the sides are inset so standing flush against a wall is fine.
 * Rays along every edge and face diagonal at three heights, plus the vertical edges and center: a wall crossing
 * the box always crosses one of them, and a ray that starts inside solid counts as a hit.
 */
bool HitsWorld(const float pos[3], float yaw, const float mins[3], const float maxs[3])
{
	float zLo = mins[2] + PLACE_STEP;
	float zHi = maxs[2] - PLACE_INSET;
	if (zLo > zHi)
		zLo = zHi;

	float pts[5][3];
	FootprintPoints(pos, yaw, mins, maxs, pts);

	float h[3];
	h[0] = zLo;
	h[1] = (zLo + zHi) * 0.5;
	h[2] = zHi;

	// Corner pairs: the 4 sides and the 2 diagonals.
	static const int pairs[6][2] = { {1, 2}, {2, 3}, {3, 4}, {4, 1}, {1, 3}, {2, 4} };

	for (int l = 0; l < 3; l++)
	{
		for (int p = 0; p < 6; p++)
		{
			float a[3], b[3];
			a = pts[pairs[p][0]];
			b = pts[pairs[p][1]];
			a[2] = pos[2] + h[l];
			b[2] = pos[2] + h[l];
			if (RayBlocked(a, b))
				return true;
		}
	}

	for (int i = 0; i < 5; i++)
	{
		float a[3], b[3];
		a = pts[i];
		b = pts[i];
		a[2] = pos[2] + zLo;
		b[2] = pos[2] + zHi;
		if (RayBlocked(a, b))
			return true;
	}
	return false;
}

bool RayBlocked(const float a[3], const float b[3])
{
	TR_TraceRayFilter(a, b, MASK_SOLID, RayType_EndPoint, WorldFilter);
	return TR_DidHit() || TR_StartSolid();
}

// World geometry only: the map itself (and its static props) and brush entities. Players, props and
// fortifications don't count.
public bool WorldFilter(int entity, int contentsMask)
{
	if (entity == 0)
		return true;
	if (entity <= MaxClients || !IsValidEntity(entity))
		return false;

	char cls[32];
	GetEdictClassname(entity, cls, sizeof(cls));
	return strncmp(cls, "func_", 5) == 0;
}

// True if any living player is standing inside the (yaw-rotated) box.
bool PlayersOverlap(const float pos[3], float yaw, const float mins[3], const float maxs[3])
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || !IsPlayerAlive(i))
			continue;

		float org[3];
		GetClientAbsOrigin(i, org);
		if (PointInBox(org, pos, yaw, mins, maxs, 18.0, 71.0, 0.0))
			return true;
	}
	return false;
}

/* ------------------------------------------------------------------ */
/*  Hologram preview                                                  */
/* ------------------------------------------------------------------ */

// Barbed wire is the only buildable whose model has no .phy, so it can't use solid 6: that asks the engine, on the
// server and on every client, for a collision model that doesn't exist.
bool TypeHasCollision(int type)
{
	return type != TYPE_WIRE;
}

// Call before DispatchSpawn. Dynamic shadows would redraw the model into the shadow texture, every tick for a hologram.
void SetupPropRendering(int ent, int type)
{
	DispatchKeyValue(ent, "disableshadows", "1");
	DispatchKeyValue(ent, "disablereceiveshadows", "1");

	if (type == TYPE_WIRE)
	{
		char buf[16];
		IntToString(WIRE_FADE_MIN, buf, sizeof(buf));
		DispatchKeyValue(ent, "fademindist", buf);
		IntToString(WIRE_FADE_MAX, buf, sizeof(buf));
		DispatchKeyValue(ent, "fademaxdist", buf);
	}
}

void SetGlow(int ent, int color)
{
	SetEntProp(ent, Prop_Send, "m_iGlowType", 3);
	SetEntProp(ent, Prop_Send, "m_nGlowRange", GLOW_RANGE);
	SetEntProp(ent, Prop_Send, "m_glowColorOverride", color);
}

bool AimMoved(const float pos[3], float yaw, const float lastPos[3], float lastYaw)
{
	return GetVectorDistance(pos, lastPos, true) >= GHOST_MOVE_SQR || FloatAbs(yaw - lastYaw) >= GHOST_YAW;
}

// CanPlace runs a lot of traces and nav lookups, so its result is reused while the aim stays put. force = always recheck.
int CanPlaceCached(int client, int userid, int type, const float pos[3], float yaw, bool force)
{
	float now = GetGameTime();
	if (force || now >= g_PlaceNext[client] || type != g_PlaceType[client] || AimMoved(pos, yaw, g_PlacePos[client], g_PlaceYaw[client]))
	{
		g_PlaceReason[client] = CanPlace(userid, type, pos, yaw);
		g_PlaceType[client]   = type;
		g_PlaceYaw[client]    = yaw;
		g_PlaceNext[client]   = now + PLACE_RECHECK;
		for (int i = 0; i < 3; i++)
			g_PlacePos[client][i] = pos[i];
	}
	return g_PlaceReason[client];
}

void UpdateGhost(int client, int type, const float pos[3], const float ang[3], bool valid)
{
	int ghost = EntRefToEntIndex(g_GhostRef[client]);
	bool fresh = false;

	// The selected type changed: rebuild the hologram with the right model.
	if (ghost != INVALID_ENT_REFERENCE && g_GhostType[client] != type)
	{
		RemoveGhost(client);
		ghost = INVALID_ENT_REFERENCE;
	}

	if (ghost == INVALID_ENT_REFERENCE)
	{
		ghost = CreateGhost(client, type);
		if (ghost == -1)
			return;
		g_GhostRef[client]   = EntIndexToEntRef(ghost);
		g_GhostType[client]  = type;
		g_GhostState[client] = 0;
		fresh = true;
	}

	int state = valid ? 1 : 2;
	if (g_GhostState[client] != state)
	{
		g_GhostState[client] = state;
		int r  = valid ? 0 : 255;
		int gr = valid ? 255 : 40;
		int b  = valid ? 160 : 40;
		ColorGhost(ghost, r, gr, b);

		int wire = EntRefToEntIndex(g_GhostWireRef[client]);
		if (wire != INVALID_ENT_REFERENCE)
			ColorGhost(wire, r, gr, b);
	}

	if (fresh || AimMoved(pos, ang[1], g_GhostPos[client], g_GhostYaw[client]))
	{
		TeleportEntity(ghost, pos, ang, NULL_VECTOR);
		g_GhostYaw[client] = ang[1];
		for (int i = 0; i < 3; i++)
			g_GhostPos[client][i] = pos[i];
	}
}

int CreateGhost(int client, int type)
{
	int ent = CreateEntityByName("prop_dynamic_override");
	if (ent == -1)
		return -1;

	SetEntityModel(ent, g_TypeModel[type]);
	DispatchKeyValue(ent, "targetname", GHOST_NAME);
	DispatchKeyValue(ent, "solid", "0");
	SetupPropRendering(ent, type);
	DispatchSpawn(ent);

	SetEntityRenderMode(ent, RENDER_TRANSCOLOR);
	SetEntityRenderColor(ent, 0, 255, 160, 150);

	float mins[3], maxs[3];
	ReadBounds(ent, type, mins, maxs);

	g_GhostOwner[ent] = client;
	SDKHook(ent, SDKHook_SetTransmit, Hook_GhostTransmit);

	// Spawned at the world origin, so the wire's position is the offset itself. It follows the hologram from here on.
	g_GhostWireRef[client] = -1;
	if (type == TYPE_BARRICADE)
	{
		float origin[3];
		int wire = AttachBarricadeWire(ent, origin, 0.0);
		if (wire != -1)
		{
			SetEntityRenderMode(wire, RENDER_TRANSCOLOR);
			g_GhostOwner[wire] = client;
			SDKHook(wire, SDKHook_SetTransmit, Hook_GhostTransmit);
			g_GhostWireRef[client] = EntIndexToEntRef(wire);
		}
	}
	return ent;
}

void ColorGhost(int ent, int r, int g, int b)
{
	SetEntityRenderColor(ent, r, g, b, 150);

	if (g_cvGlow.BoolValue)
		SetGlow(ent, r + (g << 8) + (b << 16));
}

// Shared by the placement hologram and the crit marker: only the owner can see them.
public Action Hook_GhostTransmit(int entity, int client)
{
	return (g_GhostOwner[entity] == client) ? Plugin_Continue : Plugin_Handled;
}

void RemoveGhost(int client)
{
	if (client < 1 || client > MaxClients)
		return;

	int ghost = EntRefToEntIndex(g_GhostRef[client]);
	if (ghost != INVALID_ENT_REFERENCE)
	{
		g_GhostOwner[ghost] = 0;

		int wire = EntRefToEntIndex(g_GhostWireRef[client]);
		if (wire != INVALID_ENT_REFERENCE)
			g_GhostOwner[wire] = 0;

		AcceptEntityInput(ghost, "KillHierarchy");
	}
	g_GhostRef[client]   = -1;
	g_GhostWireRef[client] = -1;
	g_GhostState[client] = 0;
}

/* ------------------------------------------------------------------ */
/*  Creating fortifications                                           */
/* ------------------------------------------------------------------ */

/**
 * Spawns the see-through, non-collide, non-functional construction prop and adds it to the list.
 * Enforces the global per-player limit by destroying the player's oldest fortification.
 * Returns the list index, or -1 on failure.
 */
int CreateFort(int client, int userid, int type, const float pos[3], const float ang[3])
{
	int guard = 0;
	while (CountOwnedAll(userid) >= g_cvMaxTotal.IntValue && guard < 16)
	{
		guard++;
		if (!DestroyOldest(userid))
			break;
		//PrintHint(client, "Fortification limit reached (%d): your oldest fortification was destroyed.", g_cvMaxTotal.IntValue);
	}

	if (g_Forts.Length >= MAX_FORTS)
	{
		PrintHint(client, "Too many fortifications on the map right now.");
		return -1;
	}

	int slot = -1;
	if (type == TYPE_WIRE || type == TYPE_BARRICADE)
	{
		slot = AllocSlot();
		if (slot == -1)
		{
			PrintHint(client, "Too many barbed wires on the map right now.");
			return -1;
		}
	}

	int ent = CreateEntityByName("prop_dynamic_override");
	if (ent == -1)
	{
		if (slot != -1)
			g_SlotUsed[slot] = false;
		return -1;
	}

	SetEntityModel(ent, g_TypeModel[type]);
	DispatchKeyValue(ent, "targetname", FORT_NAME);
	// Solid 6 gives the prop its real physics shape, so rays (crit marker placement) hit the actual surface.
	// Debris collision group means players and infected still walk straight through it.
	DispatchKeyValue(ent, "solid", TypeHasCollision(type) ? "6" : "0");
	SetupPropRendering(ent, type);
	DispatchSpawn(ent);
	TeleportEntity(ent, pos, ang, NULL_VECTOR);
	SetEntProp(ent, Prop_Send, "m_CollisionGroup", 1);	// COLLISION_GROUP_DEBRIS

	FortData w;
	w.ref           = EntIndexToEntRef(ent);
	w.type          = type;
	w.slot          = slot;
	w.wireRef       = -1;
	w.ownerUserId   = userid;
	w.yaw           = ang[1];
	w.done          = false;
	w.progress      = 0.0;
	w.glowOn        = false;
	w.glowNear      = false;
	w.hasMarker     = false;
	w.alpha         = 140;
	for (int i = 0; i < 3; i++)
		w.pos[i] = pos[i];

	float mins[3], maxs[3];
	ReadBounds(ent, type, mins, maxs);
	for (int i = 0; i < 3; i++)
	{
		w.mins[i] = mins[i];
		w.maxs[i] = maxs[i];
	}

	SetEntityRenderMode(ent, RENDER_TRANSCOLOR);
	SetEntityRenderColor(ent, 255, 200, 80, w.alpha);

	// Thin models (barbed wire) are nearly invisible when translucent, so unfinished
	// fortifications get an orange outline that shows through everything.
	if (g_cvGlow.BoolValue)
	{
		SetGlow(ent, 255 + (140 << 8));	// orange
		w.glowOn = true;
	}

	// Without the model there is nothing to warn players, so no damage either.
	if (type == TYPE_BARRICADE)
	{
		int wire = AttachBarricadeWire(ent, pos, ang[1]);
		if (wire != -1)
		{
			SetEntityRenderMode(wire, RENDER_TRANSCOLOR);
			SetEntityRenderColor(wire, 255, 200, 80, w.alpha);
			w.wireRef = EntIndexToEntRef(wire);
		}
		else
		{
			g_SlotUsed[w.slot] = false;
			w.slot = -1;
		}
	}

	g_Forts.PushArray(w);
	return g_Forts.Length - 1;
}

/**
 * Turns a finished construction into the real thing.
 * Returns 0 = done, 1 = blocked by a player (try again later), 2 = failed (entry erased).
 */
int FinalizeFort(int index)
{
	FortData w;
	g_Forts.GetArray(index, w);

	int ent = EntRefToEntIndex(w.ref);
	if (ent == INVALID_ENT_REFERENCE)
	{
		EraseFort(index);
		return 2;
	}

	// Solid fortifications must not trap someone who is standing inside them.
	if (w.type != TYPE_WIRE && PlayersOverlap(w.pos, w.yaw, w.mins, w.maxs))
		return 1;

	StopBuildSound(ent, w.type);

	if (w.glowOn)
		SetEntProp(ent, Prop_Send, "m_iGlowType", 0);

	switch (w.type)
	{
		case TYPE_WALL, TYPE_BARRICADE:
		{
			SetEntityRenderMode(ent, RENDER_NORMAL);
			SetEntityRenderColor(ent, 255, 255, 255, 255);
			SetEntProp(ent, Prop_Send, "m_CollisionGroup", 0);	// back to a normal solid
			AcceptEntityInput(ent, "EnableCollision");

			int wire = EntRefToEntIndex(w.wireRef);
			if (wire != INVALID_ENT_REFERENCE)
			{
				SetEntityRenderMode(wire, RENDER_NORMAL);
				SetEntityRenderColor(wire, 255, 255, 255, 255);
			}
		}
		case TYPE_CAL, TYPE_MINIGUN:
		{
			// Replace the construction prop with the real, usable emplacement.
			float ang[3];
			ang[1] = w.yaw;

			AcceptEntityInput(ent, "Kill");
			int cal = SpawnEmplacement(w.type, w.pos, ang);
			if (cal == -1)
			{
				EraseFort(index);
				return 2;
			}

			w.ref = EntIndexToEntRef(cal);

			float cmins[3], cmaxs[3];
			ReadBounds(cal, w.type, cmins, cmaxs);
			for (int i = 0; i < 3; i++)
			{
				w.mins[i] = cmins[i];
				w.maxs[i] = cmaxs[i];
			}
		}
		default:
		{
			SetEntityRenderMode(ent, RENDER_NORMAL);
			SetEntityRenderColor(ent, 255, 255, 255, 255);
		}
	}

	w.done     = true;
	w.alpha    = 255;
	w.progress = 100.0;
	g_Forts.SetArray(index, w);

	return 0;
}

// The barbed wire on a barricade, also its blueprint and hologram. Only the model: it isn't in the fortification list,
// its damage and slowdown come from the finished barricade's own entry (see ProcessTarget), and it is removed along with
// its parent. pos and yaw are the parent's. Returns the entity, or -1.
int AttachBarricadeWire(int parent, const float pos[3], float yaw)
{
	int wire = CreateEntityByName("prop_dynamic_override");
	if (wire == -1)
		return -1;

	SetEntityModel(wire, MODEL_WIRE);
	DispatchKeyValue(wire, "targetname", FORT_NAME);
	DispatchKeyValue(wire, "solid", "0");
	SetupPropRendering(wire, TYPE_WIRE);
	DispatchSpawn(wire);

	float world[3], ang[3];
	LocalToWorld(pos, yaw, g_BarricadeWirePos, world);
	ang[0] = 0.0;
	ang[1] = yaw;
	TeleportEntity(wire, world, ang, NULL_VECTOR);

	SetVariantString("!activator");
	AcceptEntityInput(wire, "SetParent", parent);
	return wire;
}

// SourceMod equivalent of:
//   SpawnEntityFromTable("prop_minigun", {MinPitch = -25, MaxPitch = 50, MaxYaw = 90, origin = pos, angles = ang})
int SpawnEmplacement(int type, const float pos[3], const float ang[3])
{
	// In L4D2 "prop_minigun" is the .50 cal; the regular minigun is "prop_minigun_l4d1".
	int ent = CreateEntityByName((type == TYPE_MINIGUN) ? "prop_minigun_l4d1" : "prop_minigun");
	if (ent == -1)
		return -1;

	DispatchKeyValue(ent, "model", (type == TYPE_MINIGUN) ? MODEL_MINIGUN : MODEL_CAL);
	DispatchKeyValue(ent, "targetname", FORT_NAME);
	DispatchKeyValue(ent, "MinPitch", "-25");
	DispatchKeyValue(ent, "MaxPitch", "50");
	DispatchKeyValue(ent, "MaxYaw", "90");
	DispatchKeyValueVector(ent, "origin", pos);
	DispatchKeyValueVector(ent, "angles", ang);
	DispatchSpawn(ent);
	ActivateEntity(ent);
	return ent;
}

/* ------------------------------------------------------------------ */
/*  Blueprints, swings and crit markers                               */
/* ------------------------------------------------------------------ */

void PlaceBlueprint(int client, int userid, int type, const float pos[3], const float ang[3])
{
	int idx = CreateFort(client, userid, type, pos, ang);
	if (idx == -1)
		return;

	Hint(client, "%s blueprint placed (%d/%d). Leave build mode and swing at it - hit the marker for big progress.", g_TypeName[type], CountOwnedAll(userid), g_cvMaxTotal.IntValue);
}

// Blueprints become more opaque and shift from orange to white as they are built.
void UpdateBlueprintVisual(int ent, int wireRef, float progress)
{
	float p = progress / 100.0;
	int a = 140 + RoundToFloor(115.0 * p);
	int g = 200 + RoundToFloor(55.0 * p);
	int b = 80 + RoundToFloor(175.0 * p);
	SetEntityRenderColor(ent, 255, g, b, a);

	int wire = EntRefToEntIndex(wireRef);
	if (wire != INVALID_ENT_REFERENCE)
		SetEntityRenderColor(wire, 255, g, b, a);
}

void AddProgress(int idx, float amount, int client)
{
	FortData w;
	g_Forts.GetArray(idx, w);

	int ent = EntRefToEntIndex(w.ref);
	if (ent == INVALID_ENT_REFERENCE)
		return;

	w.progress += amount;
	if (w.progress > 100.0)
		w.progress = 100.0;

	UpdateBlueprintVisual(ent, w.wireRef, w.progress);

	// Nearly done: a green outline shows through everything.
	if (!w.glowNear && w.progress >= 75.0 && g_cvGlow.BoolValue)
	{
		w.glowNear = true;
		w.glowOn   = true;
		SetGlow(ent, 80 << 8);	// green
	}

	g_Forts.SetArray(idx, w);

	if (w.progress >= 100.0)
	{
		int result = FinalizeFort(idx);
		if (result == 1)
			PrintCenterText(client, "Area blocked - it will finish once it is clear.");
	}
}

// A swing was started: a crit lands if the marker is visible from where the player stands (right side of
// the surface, in reach, clear line of sight) and the swing passes close to it. Otherwise any blueprint in
// the swing path still gets the reduced, non-crit progress.
void HandleSwing(int client, const float eye[3], const float fwd[3])
{
	float range = g_cvMelee.FloatValue;

	int  idx  = -1;
	bool crit = false;

	for (int i = g_Forts.Length - 1; i >= 0; i--)
	{
		FortData cw;
		g_Forts.GetArray(i, cw);

		if (cw.done || !cw.hasMarker)
			continue;

		if (RayPointDistance(eye, fwd, range, cw.mpos) > g_cvCritRadius.FloatValue)
			continue;

		// Same visibility rules as the marker itself: wrong side of the prop = no crit.
		if (!MarkerPointValid(eye, cw.mpos, cw.mnorm))
			continue;

		idx  = i;
		crit = true;
		break;
	}

	if (idx == -1)
		idx = FindBlueprintInRay(eye, fwd, range);
	if (idx == -1)
		return;

	FortData w;
	g_Forts.GetArray(idx, w);

	int ent = EntRefToEntIndex(w.ref);
	if (ent == INVALID_ENT_REFERENCE)
		return;

	int crits = g_cvCrits[w.type].IntValue;
	if (crits < 1)
		crits = 1;

	float step   = 100.0 / float(crits);
	float amount = crit ? step : step * g_cvNonCrit.FloatValue;

	int type = w.type;
	int ref  = w.ref;

	PlayConstructionHit(ent, type);
	if (crit)
		EmitSoundToClient(client, SND_MARKER_HIT);

	AddProgress(idx, amount, client);

	// The marker only ever moves when it was hit.
	if (crit)
	{
		int idx2 = FindFortByRef(ref);
		if (idx2 != -1)
		{
			FortData w2;
			g_Forts.GetArray(idx2, w2);
			if (!w2.done)
			{
				// Nothing reachable in view: drop the marker, UpdateMarker places a new one once the player
				// faces the blueprint again (so the same spot can't be hit twice).
				if (!MoveMarkerAlongLine(idx2, eye, fwd) && !PlaceMarker(idx2, eye, fwd))
				{
					w2.hasMarker = false;
					g_Forts.SetArray(idx2, w2);
				}
			}
		}
	}
}

/* ---- Geometry helpers ---------------------------------------------- */

void LocalToWorld(const float pos[3], float yaw, const float local[3], float out[3])
{
	float rad = DegToRad(yaw);
	float c = Cosine(rad);
	float s = Sine(rad);
	out[0] = pos[0] + local[0] * c - local[1] * s;
	out[1] = pos[1] + local[0] * s + local[1] * c;
	out[2] = pos[2] + local[2];
}

void RotateYaw(const float v[3], float yaw, float out[3])
{
	float rad = DegToRad(yaw);
	float c = Cosine(rad);
	float s = Sine(rad);
	out[0] = v[0] * c - v[1] * s;
	out[1] = v[0] * s + v[1] * c;
	out[2] = v[2];
}

// Faces of the box in local space: 0 = +X, 1 = -X, 2 = +Y, 3 = -Y, 4 = top (+Z).
void FaceNormal(int face, float n[3])
{
	n[0] = 0.0; n[1] = 0.0; n[2] = 0.0;
	if (face == 0)      n[0] =  1.0;
	else if (face == 1) n[0] = -1.0;
	else if (face == 2) n[1] =  1.0;
	else if (face == 3) n[1] = -1.0;
	else                n[2] =  1.0;
}

void FacePoint(int face, const float mins[3], const float maxs[3], float u, float v, float out[3])
{
	if (face == 0 || face == 1)
	{
		out[0] = (face == 0) ? maxs[0] : mins[0];
		out[1] = mins[1] + (maxs[1] - mins[1]) * u;
		out[2] = mins[2] + (maxs[2] - mins[2]) * v;
	}
	else if (face == 2 || face == 3)
	{
		out[0] = mins[0] + (maxs[0] - mins[0]) * u;
		out[1] = (face == 2) ? maxs[1] : mins[1];
		out[2] = mins[2] + (maxs[2] - mins[2]) * v;
	}
	else
	{
		out[0] = mins[0] + (maxs[0] - mins[0]) * u;
		out[1] = mins[1] + (maxs[1] - mins[1]) * v;
		out[2] = maxs[2];
	}
}

// Distance from a point to the segment eye -> eye + fwd * range.
float RayPointDistance(const float eye[3], const float fwd[3], float range, const float pt[3])
{
	float rel[3];
	for (int i = 0; i < 3; i++)
		rel[i] = pt[i] - eye[i];

	float t = GetVectorDotProduct(rel, fwd);
	t = ClampF(t, 0.0, range);

	float closest[3];
	for (int i = 0; i < 3; i++)
		closest[i] = eye[i] + fwd[i] * t;

	return GetVectorDistance(pt, closest);
}

// Shortest distance from a world point to the (yaw-rotated) box.
float DistToBox(const float pt[3], const float origin[3], float yaw, const float mins[3], const float maxs[3])
{
	float dx = pt[0] - origin[0];
	float dy = pt[1] - origin[1];
	float dz = pt[2] - origin[2];

	float rad = DegToRad(yaw);
	float c = Cosine(rad);
	float s = Sine(rad);

	float lx =  dx * c + dy * s;
	float ly = -dx * s + dy * c;

	float ex = lx - ClampF(lx, mins[0], maxs[0]);
	float ey = ly - ClampF(ly, mins[1], maxs[1]);
	float ez = dz - ClampF(dz, mins[2], maxs[2]);

	return SquareRoot(ex * ex + ey * ey + ez * ez);
}

// First unfinished blueprint along the aim ray (within range), or -1.
int FindBlueprintInRay(const float eye[3], const float fwd[3], float range)
{
	float pt[3];
	for (float t = 0.0; t <= range; t += 6.0)
	{
		for (int i = 0; i < 3; i++)
			pt[i] = eye[i] + fwd[i] * t;

		for (int i = g_Forts.Length - 1; i >= 0; i--)
		{
			FortData w;
			g_Forts.GetArray(i, w);

			if (w.done)
				continue;

			if (PointInBox(pt, w.pos, w.yaw, w.mins, w.maxs, 8.0, 6.0, 6.0))
				return i;
		}
	}
	return -1;
}

/* ---- Crit marker ---------------------------------------------------- */

// Draws a crit marker as a small red X lying flat on the surface it sits on.
// Temp entities are sent to this player only. No halo sprite is used.
// The X always faces the player. It is pulled toward their eyes, which doesn't move it on screen but keeps its arms
// out of the surface it sits on.
void DrawMarkerAt(int client, const float pos[3], const float eye[3], bool aimed)
{
	int normalColor[4] = MARKER_COLOR;
	int aimedColor[4]  = MARKER_COLOR_AIMED;
	int color[4];
	color = aimed ? aimedColor : normalColor;

	float n[3], p[3];
	MakeVectorFromPoints(pos, eye, n);
	NormalizeVector(n, n);

	float arm = MARKER_SIZE;
	for (int i = 0; i < 3; i++)
		p[i] = pos[i] + n[i] * (arm + 1.0);

	// Two directions across the player's view. Looking straight up or down, world up can't be used for this.
	float axis[3] = {0.0, 0.0, 1.0};
	if (FloatAbs(n[2]) > 0.9)
	{
		axis[0] = 1.0;
		axis[2] = 0.0;
	}

	float t1[3], t2[3];
	GetVectorCrossProduct(n, axis, t1);
	NormalizeVector(t1, t1);
	GetVectorCrossProduct(n, t1, t2);
	NormalizeVector(t2, t2);

	float d1[3], d2[3];
	for (int i = 0; i < 3; i++)
	{
		d1[i] = (t1[i] + t2[i]) * 0.7071;
		d2[i] = (t1[i] - t2[i]) * 0.7071;
	}

	float a[3], b[3];
	for (int i = 0; i < 3; i++)
	{
		a[i] = p[i] - d1[i] * arm;
		b[i] = p[i] + d1[i] * arm;
	}
	TE_SetupBeamPoints(a, b, g_BeamSprite, 0, 0, 15, 0.1, MARKER_WIDTH, MARKER_WIDTH, 0, 0.0, color, 0);
	TE_SendToClient(client);

	for (int i = 0; i < 3; i++)
	{
		a[i] = p[i] - d2[i] * arm;
		b[i] = p[i] + d2[i] * arm;
	}
	TE_SetupBeamPoints(a, b, g_BeamSprite, 0, 0, 15, 0.1, MARKER_WIDTH, MARKER_WIDTH, 0, 0.0, color, 0);
	TE_SendToClient(client);
}

/**
 * A marker is visible/hittable only if it is within melee range of the player's eyes, on a surface that
 * points toward the player, and in clear line of sight. Otherwise it is simply hidden; it never moves.
 */
bool MarkerPointValid(const float eye[3], const float worldP[3], const float normal[3])
{
	if (GetVectorDistance(eye, worldP) > g_cvMelee.FloatValue)
		return false;

	float toEye[3];
	MakeVectorFromPoints(worldP, eye, toEye);
	NormalizeVector(toEye, toEye);
	if (GetVectorDotProduct(normal, toEye) < 0.15)
		return false;

	TR_TraceRayFilter(eye, worldP, MASK_SOLID, RayType_EndPoint, TraceFilter, 0);
	if (TR_DidHit() && TR_GetFraction() < 0.98)
		return false;

	return true;
}

// Is the point inside the part of the player's view where markers may appear (see MARKER_VIEW_*)?
bool MarkerInView(const float eye[3], const float fwd[3], const float pt[3])
{
	float ang[3], f[3], right[3], up[3];
	GetVectorAngles(fwd, ang);
	GetAngleVectors(ang, f, right, up);

	float to[3];
	MakeVectorFromPoints(eye, pt, to);

	float x = GetVectorDotProduct(to, f);
	if (x <= 1.0)
		return false;

	float side = RadToDeg(ArcTangent(FloatAbs(GetVectorDotProduct(to, right)) / x));
	float vert = RadToDeg(ArcTangent(GetVectorDotProduct(to, up) / x));

	return side <= MARKER_VIEW_SIDE && vert <= MARKER_VIEW_UP && vert >= -MARKER_VIEW_DOWN;
}

/**
 * Finds a point on the entity's REAL collision shape (not its bounding box) by firing a ray from
 * 'from' to 'to' and clipping it to the entity. Returns false if the ray misses the shape.
 */
bool SurfaceHit(int ent, const float from[3], const float to[3], float hit[3], float normal[3])
{
	Handle tr = TR_ClipRayToEntityEx(from, to, MASK_ALL, RayType_EndPoint, ent);
	bool ok = TR_DidHit(tr);
	if (ok)
	{
		TR_GetEndPosition(hit, tr);
		TR_GetPlaneNormal(tr, normal);
		NormalizeVector(normal, normal);
	}
	delete tr;
	return ok;
}

// Fallback for models with no collision mesh (e.g. the .50 cal): a box shrunk toward the model's core,
// so markers don't float out in empty air around thin or irregular models.
void ShrunkBounds(const float mins[3], const float maxs[3], float smin[3], float smax[3])
{
	for (int i = 0; i < 3; i++)
	{
		float c = (mins[i] + maxs[i]) * 0.5;
		float h = (maxs[i] - mins[i]) * 0.5;
		if (i == 2)
		{
			smin[i] = mins[i];
			smax[i] = mins[i] + (maxs[i] - mins[i]) * 0.7;
		}
		else
		{
			smin[i] = c - h * 0.45;
			smax[i] = c + h * 0.45;
		}
	}
}

// Nearest point on the shrunk box's surface to a world point (used to slide a fallback marker along a line).
void BoxSurfaceNear(const float pos[3], float yaw, const float mins[3], const float maxs[3], const float T[3], float hit[3], float normal[3])
{
	float smin[3], smax[3];
	ShrunkBounds(mins, maxs, smin, smax);

	float dx = T[0] - pos[0];
	float dy = T[1] - pos[1];
	float rad = DegToRad(yaw);
	float c = Cosine(rad);
	float s = Sine(rad);

	float cl[3];
	cl[0] = ClampF( dx * c + dy * s, smin[0], smax[0]);
	cl[1] = ClampF(-dx * s + dy * c, smin[1], smax[1]);
	cl[2] = ClampF(T[2] - pos[2],    smin[2], smax[2]);

	// Push the point out to the closest of the five usable faces (no underside).
	float best = 100000.0;
	int   axis = 0;
	float sign = 1.0;
	for (int a = 0; a < 3; a++)
	{
		float lo = cl[a] - smin[a];
		float hi = smax[a] - cl[a];
		if (!(a == 2) && lo < best)
		{
			best = lo; axis = a; sign = -1.0;
		}
		if (hi < best)
		{
			best = hi; axis = a; sign = 1.0;
		}
	}
	cl[axis] = (sign > 0.0) ? smax[axis] : smin[axis];

	float nl[3];
	nl[0] = 0.0; nl[1] = 0.0; nl[2] = 0.0;
	nl[axis] = sign;

	LocalToWorld(pos, yaw, cl, hit);
	RotateYaw(nl, yaw, normal);
}

void SetFortMarker(int idx, const float pos[3], const float normal[3], const float dir[3])
{
	FortData w;
	g_Forts.GetArray(idx, w);

	w.hasMarker = true;
	for (int i = 0; i < 3; i++)
	{
		w.mpos[i]  = pos[i];
		w.mnorm[i] = normal[i];
		w.mdir[i]  = dir[i];
	}
	g_Forts.SetArray(idx, w);
}

// The line a marker follows: along the longer horizontal side of the buildable, random way round.
void MarkerLineDir(float yaw, const float mins[3], const float maxs[3], float dir[3])
{
	float axis[3];
	axis[0] = 1.0; axis[1] = 0.0; axis[2] = 0.0;
	if ((maxs[1] - mins[1]) > (maxs[0] - mins[0]))
	{
		axis[0] = 0.0; axis[1] = 1.0;
	}
	RotateYaw(axis, yaw, dir);
	if (GetRandomInt(0, 1) == 1)
		ScaleVector(dir, -1.0);
}

/**
 * Creates the blueprint's marker (only when it has none yet, or after a hit when it could not slide).
 * Rays are fired from outside the bounding box through the model, so it lands on real geometry.
 */
bool PlaceMarker(int idx, const float eye[3], const float fwd[3])
{
	FortData w;
	g_Forts.GetArray(idx, w);

	int ent = EntRefToEntIndex(w.ref);
	if (ent == INVALID_ENT_REFERENCE)
		return false;

	int type = w.type;

	if (g_TypeSurf[type] != 2)
	{
		bool hitAny = false;
		for (int attempt = 0; attempt < 48; attempt++)
		{
			int   face = GetRandomInt(0, 4);
			float u    = GetRandomFloat(0.1, 0.9);
			float v    = GetRandomFloat(0.1, 0.9);

			float lp[3], nl[3], start[3], depth[3];
			FacePoint(face, w.mins, w.maxs, u, v, lp);
			FaceNormal(face, nl);

			float span = (face <= 1) ? (w.maxs[0] - w.mins[0]) : ((face <= 3) ? (w.maxs[1] - w.mins[1]) : (w.maxs[2] - w.mins[2]));
			for (int i = 0; i < 3; i++)
			{
				start[i] = lp[i] + nl[i] * 12.0;
				depth[i] = lp[i] - nl[i] * (span + 4.0);
			}

			float ws[3], we[3];
			LocalToWorld(w.pos, w.yaw, start, ws);
			LocalToWorld(w.pos, w.yaw, depth, we);

			float hit[3], hn[3];
			if (!SurfaceHit(ent, ws, we, hit, hn))
				continue;

			hitAny = true;
			if (!MarkerPointValid(eye, hit, hn) || !MarkerInView(eye, fwd, hit))
				continue;

			float dir[3];
			MarkerLineDir(w.yaw, w.mins, w.maxs, dir);
			SetFortMarker(idx, hit, hn, dir);
			g_TypeSurf[type]     = 1;
			g_TypeSurfMiss[type] = 0;
			return true;
		}

		if (hitAny)
		{
			g_TypeSurf[type]     = 1;
			g_TypeSurfMiss[type] = 0;
			return false;
		}

		// Not a single ray touched the model. After a few such tries, assume it has no collision mesh.
		g_TypeSurfMiss[type]++;
		if (g_TypeSurfMiss[type] >= 3)
		{
			g_TypeSurf[type] = 2;
			LogMessage("[Fortifications] %s has no usable collision mesh: crit markers use a shrunk bounding box for it.", g_TypeName[type]);
		}
		else
		{
			return false;
		}
	}

	// Fallback: random spot on the shrunk box.
	float smin[3], smax[3];
	ShrunkBounds(w.mins, w.maxs, smin, smax);

	for (int attempt = 0; attempt < 48; attempt++)
	{
		int   face = GetRandomInt(0, 4);
		float u    = GetRandomFloat(0.1, 0.9);
		float v    = GetRandomFloat(0.1, 0.9);

		float lp[3], nl[3], hit[3], hn[3];
		FacePoint(face, smin, smax, u, v, lp);
		FaceNormal(face, nl);
		LocalToWorld(w.pos, w.yaw, lp, hit);
		RotateYaw(nl, w.yaw, hn);

		if (!MarkerPointValid(eye, hit, hn) || !MarkerInView(eye, fwd, hit))
			continue;

		float dir[3];
		MarkerLineDir(w.yaw, w.mins, w.maxs, dir);
		SetFortMarker(idx, hit, hn, dir);
		return true;
	}
	return false;
}

/**
 * Called only after the marker was hit. It jumps along its line (never further than
 * sm_fortifications_marker_move) and keeps the line's direction while it can; when that runs out of valid,
 * reachable surface it reverses, then turns sideways, then up/down. The new spot must be valid for the
 * player who hit it, so following the line means walking along the buildable.
 */
bool MoveMarkerAlongLine(int idx, const float eye[3], const float fwd[3])
{
	FortData w;
	g_Forts.GetArray(idx, w);

	int ent = EntRefToEntIndex(w.ref);
	if (ent == INVALID_ENT_REFERENCE || !w.hasMarker)
		return false;

	float oldP[3], oldN[3], dir[3];
	for (int i = 0; i < 3; i++)
	{
		oldP[i] = w.mpos[i];
		oldN[i] = w.mnorm[i];
		dir[i]  = w.mdir[i];
	}
	if (GetVectorLength(dir) < 0.01)
	{
		dir[0] = 1.0; dir[1] = 0.0; dir[2] = 0.0;
	}
	NormalizeVector(dir, dir);

	float cands[6][3];
	for (int i = 0; i < 3; i++)
	{
		cands[0][i] = dir[i];
		cands[1][i] = -dir[i];
	}
	cands[2][0] = -dir[1]; cands[2][1] =  dir[0]; cands[2][2] = 0.0;
	cands[3][0] =  dir[1]; cands[3][1] = -dir[0]; cands[3][2] = 0.0;
	cands[4][0] = 0.0; cands[4][1] = 0.0; cands[4][2] =  1.0;
	cands[5][0] = 0.0; cands[5][1] = 0.0; cands[5][2] = -1.0;

	float maxMove = g_cvMarkerMove.FloatValue;
	float steps[4];
	steps[0] = maxMove;
	steps[1] = maxMove * 0.75;
	steps[2] = maxMove * 0.5;
	steps[3] = maxMove * 0.3;

	bool fallback = (g_TypeSurf[w.type] == 2);

	for (int c = 0; c < 6; c++)
	{
		float cd[3];
		for (int i = 0; i < 3; i++)
			cd[i] = cands[c][i];
		if (GetVectorLength(cd) < 0.01)
			continue;
		NormalizeVector(cd, cd);

		for (int k = 0; k < 4; k++)
		{
			float T[3];
			for (int i = 0; i < 3; i++)
				T[i] = oldP[i] + cd[i] * steps[k];

			for (int mth = 0; mth < 2; mth++)
			{
				float hit[3], hn[3];

				if (fallback)
				{
					if (mth == 1)
						continue;
					BoxSurfaceNear(w.pos, w.yaw, w.mins, w.maxs, T, hit, hn);
				}
				else
				{
					float from[3], to[3];
					if (mth == 0)
					{
						for (int i = 0; i < 3; i++)
						{
							from[i] = T[i] + oldN[i] * 24.0;
							to[i]   = T[i] - oldN[i] * 24.0;
						}
					}
					else
					{
						float v[3];
						MakeVectorFromPoints(eye, T, v);
						NormalizeVector(v, v);
						for (int i = 0; i < 3; i++)
						{
							from[i] = T[i] - v[i] * 20.0;
							to[i]   = T[i] + v[i] * 20.0;
						}
					}

					if (!SurfaceHit(ent, from, to, hit, hn))
						continue;
				}

				float moved = GetVectorDistance(hit, oldP);
				if (moved < 8.0 || moved > maxMove + 0.5)
					continue;

				if (!MarkerPointValid(eye, hit, hn) || !MarkerInView(eye, fwd, hit))
					continue;

				SetFortMarker(idx, hit, hn, cd);
				return true;
			}
		}
	}
	return false;
}

// Distance to the closest unfinished blueprint within 600 units, or -1.0 if there is none.
float NearestBlueprintDist(const float eye[3])
{
	float best = -1.0;
	for (int i = 0; i < g_Forts.Length; i++)
	{
		FortData w;
		g_Forts.GetArray(i, w);

		if (w.done)
			continue;

		float d = DistToBox(eye, w.pos, w.yaw, w.mins, w.maxs);
		if (d <= 600.0 && (best < 0.0 || d < best))
			best = d;
	}
	return best;
}

/**
 * Every unfinished blueprint owns one marker that never moves because of where players stand.
 * Here it is only (a) created the first time a player gets in reach, and (b) drawn for this player
 * while it is valid for them (in reach, facing them, in line of sight); otherwise it is just hidden.
 */
void UpdateMarker(int client, const float eye[3], const float fwd[3])
{
	float now   = GetGameTime();
	float range = g_cvMelee.FloatValue;

	bool draw = (now >= g_MarkerNextDraw[client]);
	if (draw)
		g_MarkerNextDraw[client] = now + 0.08;

	bool inReach = false;

	for (int i = 0; i < g_Forts.Length; i++)
	{
		FortData w;
		g_Forts.GetArray(i, w);

		if (w.done)
			continue;

		if (DistToBox(eye, w.pos, w.yaw, w.mins, w.maxs) > range + 30.0)
			continue;

		inReach = true;

		if (!w.hasMarker)
		{
			if (now >= g_MarkerNextTry[client])
			{
				g_MarkerNextTry[client] = now + 0.15;
				if (!PlaceMarker(i, eye, fwd) && now >= g_MarkerHintNext[client])
				{
					g_MarkerHintNext[client] = now + 4.0;
					Hint(client, "No reachable spot for the crit marker - face the blueprint.");
				}
			}
			continue;
		}

		if (draw && MarkerPointValid(eye, w.mpos, w.mnorm))
		{
			// Same test HandleSwing uses for a crit.
			bool aimed = (RayPointDistance(eye, fwd, range, w.mpos) <= g_cvCritRadius.FloatValue);
			DrawMarkerAt(client, w.mpos, eye, aimed);
		}
	}

	if (!inReach && NearestBlueprintDist(eye) >= 0.0 && now >= g_MarkerHintNext[client])
	{
		g_MarkerHintNext[client] = now + 4.0;
		Hint(client, "Move within knife reach of the blueprint to see its crit marker.");
	}
}

/* ------------------------------------------------------------------ */
/*  Dismantling                                                       */
/* ------------------------------------------------------------------ */

bool IsDismantling(int client)
{
	if (g_DisRef[client] == -1)
		return false;

	if (EntRefToEntIndex(g_DisRef[client]) == INVALID_ENT_REFERENCE)
	{
		g_DisRef[client] = -1;
		return false;
	}
	return true;
}

void CancelDismantle(int client, bool notify)
{
	if (client < 1 || client > MaxClients)
		return;

	if (g_DisRef[client] == -1)
		return;

	g_DisRef[client] = -1;

	if (notify && IsClientInGame(client))
		ShowStatus(client, "Dismantle cancelled.");
}

void BeginDismantleIdx(int client, int idx)
{
	FortData w;
	g_Forts.GetArray(idx, w);

	// Only the built part has to be taken apart: a 25% blueprint takes 25% of the full dismantle time.
	float time = g_cvDismantleTime[w.type].FloatValue * FortBuiltFraction(w);
	if (time <= 0.05)
	{
		CompleteDismantle(client, idx);
		return;
	}

	float now = GetGameTime();
	g_DisRef[client]   = w.ref;
	g_DisStart[client] = now;
	g_DisEnd[client]   = now + time;
	g_DisPct[client]   = -1;
}

// How much of a fortification is built, 0..1.
float FortBuiltFraction(FortData w)
{
	if (w.done)
		return 1.0;

	float frac = w.progress / 100.0;
	if (frac < 0.0)
		frac = 0.0;
	else if (frac > 1.0)
		frac = 1.0;
	return frac;
}

// The player must keep holding the dismantle button and keep aiming at the same fortification.
void TickDismantle(int client, const float eye[3], const float fwd[3], float dist, int held, int button, float now)
{
	RemoveGhost(client);

	if (!(held & button))
	{
		CancelDismantle(client, true);
		return;
	}

	int idx = FindFortAimedAt(eye, fwd, dist);
	int ref = -1;
	if (idx != -1)
	{
		FortData w;
		g_Forts.GetArray(idx, w);
		ref = w.ref;
	}

	if (idx == -1 || ref != g_DisRef[client])
	{
		CancelDismantle(client, true);
	}
	else if (now >= g_DisEnd[client])
	{
		CompleteDismantle(client, idx);
	}
	else
	{
		FortData w;
		g_Forts.GetArray(idx, w);

		float progress = (now - g_DisStart[client]) / (g_DisEnd[client] - g_DisStart[client]);
		int pct = RoundToFloor(progress * 20.0) * 5;
		g_DisPct[client] = pct;
		ShowStatus(client, "Dismantling %s... %d%%", g_TypeName[w.type], pct);
	}
}

void CompleteDismantle(int client, int idx)
{
	FortData w;
	g_Forts.GetArray(idx, w);

	EmitDismantleSound(w.type, w.pos);

	int ent = EntRefToEntIndex(w.ref);
	if (ent != INVALID_ENT_REFERENCE)
	{
		StopBuildSound(ent, w.type);
		AcceptEntityInput(ent, "KillHierarchy");
	}
	EraseFort(idx);

	g_DisRef[client] = -1;
	if (IsClientInGame(client))
		ShowStatus(client, "%s dismantled.", g_TypeName[w.type]);
}

// Nearest fortification along the aim ray, or -1.
int FindFortAimedAt(const float eye[3], const float fwd[3], float dist)
{
	float pt[3];
	for (float t = 0.0; t <= dist + 8.0; t += 6.0)
	{
		for (int i = 0; i < 3; i++)
			pt[i] = eye[i] + fwd[i] * t;

		for (int i = g_Forts.Length - 1; i >= 0; i--)
		{
			FortData w;
			g_Forts.GetArray(i, w);

			if (PointInBox(pt, w.pos, w.yaw, w.mins, w.maxs, 10.0, 6.0, 6.0))
				return i;
		}
	}
	return -1;
}

/**
 * Tests a world point against a yaw-rotated box in the fortification's local space.
 * padXY expands the box on its local X/Y, zBelow/zAbove expand it vertically.
 */
bool PointInBox(const float pt[3], const float origin[3], float yaw, const float mins[3], const float maxs[3], float padXY, float zBelow, float zAbove)
{
	float dx = pt[0] - origin[0];
	float dy = pt[1] - origin[1];
	float dz = pt[2] - origin[2];

	float rad = DegToRad(yaw);
	float c = Cosine(rad);
	float s = Sine(rad);

	float lx =  dx * c + dy * s;
	float ly = -dx * s + dy * c;

	return (lx >= mins[0] - padXY && lx <= maxs[0] + padXY
		 && ly >= mins[1] - padXY && ly <= maxs[1] + padXY
		 && dz >= mins[2] - zBelow && dz <= maxs[2] + zAbove);
}

/* ------------------------------------------------------------------ */
/*  Per-frame: finishing blueprints, barbed wire slow + damage        */
/*  (checked every server frame so fast movers can't skip the wire)   */
/* ------------------------------------------------------------------ */

public void OnGameFrame()
{
	if (g_Forts == null)
		return;

	float now = GetGameTime();

	// Prune dead entries and finish blueprints.
	for (int i = g_Forts.Length - 1; i >= 0; i--)
	{
		FortData w;
		g_Forts.GetArray(i, w);

		int ent = EntRefToEntIndex(w.ref);
		if (ent == INVALID_ENT_REFERENCE)
		{
			EraseFort(i);
			continue;
		}

		if (w.done)
			continue;

		// Blueprints are never removed for being far away. A fully built one that was blocked
		// by a player standing in the spot keeps retrying until it is clear.
		if (w.progress >= 100.0)
			FinalizeFort(i);
	}

	// Anything left to do for barbed wire?
	g_WireCount = 0;
	if (g_cvEnable.BoolValue)
	{
		for (int i = 0; i < g_Forts.Length; i++)
		{
			FortData w;
			g_Forts.GetArray(i, w);
			if (w.slot != -1 && w.done)
				g_Wires[g_WireCount++] = i;
		}
	}

	if (g_WireCount == 0)
	{
		if (g_AnySlowed)
			ResetAllSlows();
		return;
	}

	// Players
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

		// Ghost infected, and survivor bots (they can't avoid the wire): no damage, no slowdown.
		if ((team == TEAM_INFECTED && GetEntProp(client, Prop_Send, "m_isGhost") != 0)
			|| (team == TEAM_SURVIVOR && IsFakeClient(client)))
		{
			ResetSlow(client);
			continue;
		}

		float pad    = 18.0;
		float height = 71.0;
		if (team == TEAM_INFECTED && GetEntProp(client, Prop_Send, "m_zombieClass") == ZC_TANK)
		{
			pad    = 32.0;
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
		if (!IsValidEntity(ent))
			continue;

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
	if (ent <= MaxClients)
		return (IsClientInGame(ent) && IsPlayerAlive(ent));

	return (IsValidEntity(ent) && GetEntProp(ent, Prop_Data, "m_iHealth") > 0);
}

/**
 * Checks one entity against every finished barbed wire. Each wire the entity is touching
 * runs on its OWN damage timer for this entity (g_SlotNextDmg[wire][entity]), so
 * overlapping wires stack their damage. Slowing does not stack.
 */
void ProcessTarget(int ent, const float org[3], float pad, float height, bool giveOwnerCredit, float now)
{
	// Entity index may have been reused (e.g. a dead common replaced by a new one).
	int ref = EntIndexToEntRef(ent);
	if (g_TargetRef[ent] != ref)
	{
		g_TargetRef[ent]  = ref;
		g_Slowed[ent]     = false;
		g_HasLastPos[ent] = false;
		for (int s = 0; s < MAX_FORTS; s++)
			g_SlotNextDmg[s][ent] = 0.0;
	}

	bool  inside   = false;
	bool  damaged  = false;
	bool  alive    = true;
	float interval = g_cvWireInterval.FloatValue;
	bool  survivor = (ent <= MaxClients && GetClientTeam(ent) == TEAM_SURVIVOR);
	float damage   = survivor ? g_cvWireDamage.FloatValue : g_cvWireDamageInfected.FloatValue;

	for (int i = 0; i < g_WireCount; i++)
	{
		FortData w;
		g_Forts.GetArray(g_Wires[i], w);

		// A barricade's wire is only the part on top, not the whole barricade.
		bool touching = (w.type == TYPE_BARRICADE)
			? PointInBox(org, w.pos, w.yaw, g_BarricadeWireMins, g_BarricadeWireMaxs, pad, height, 0.0)
			: PointInBox(org, w.pos, w.yaw, w.mins, w.maxs, pad, height, 0.0);
		if (!touching)
			continue;

		inside = true;

		// This wire's own timer for this target.
		if (now < g_SlotNextDmg[w.slot][ent])
			continue;

		g_SlotNextDmg[w.slot][ent] = now + interval;

		int inflictor = EntRefToEntIndex(w.ref);
		if (inflictor == INVALID_ENT_REFERENCE)
			inflictor = 0;

		// Infected/common take damage credited to the wire's owner. Survivors take world damage (ignores friendly-fire rules).
		int attacker = 0;
		if (giveOwnerCredit)
		{
			int owner = GetClientOfUserId(w.ownerUserId);
			if (owner > 0 && IsClientInGame(owner))
				attacker = owner;
		}

		SDKHooks_TakeDamage(ent, inflictor, attacker, damage, DMG_SLASH);
		damaged = true;

		if (!IsTargetAlive(ent))
		{
			alive = false;
			break;
		}
	}

	// One sound per target per frame, even if several wires hit at once.
	if (damaged)
		EmitSoundToAll(SND_WIRE_DAMAGE, ent, SNDCHAN_AUTO, SNDLEVEL_NORMAL);

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
		&& g_cvWireTankImmune.BoolValue)
	{
		ResetSlow(ent);
		return;
	}

	ApplySlow(ent);

	// Common infected (NextBots) and infected players get the direct slow enforcement.
	if (ent > MaxClients || GetClientTeam(ent) == TEAM_INFECTED)
		EnforceSlow(ent, org, true);
	else
		TrackPosition(ent, org);
}

void TrackPosition(int ent, const float org[3])
{
	if (ent <= MaxClients || ent < 1 || ent > 2048)
		return;

	for (int i = 0; i < 3; i++)
		g_LastPos[ent][i] = org[i];
	g_HasLastPos[ent] = true;
}

/**
 * Directly enforces the slow while an entity is inside a barbed wire.
 *  - Common infected are NextBots: each frame the horizontal distance they actually moved is
 *    scaled down by sm_barbedwire_slow and they are put back along their path.
 *  - Infected players use the normal movement multiplier plus a velocity cap of maxspeed * slow.
 * Survivors only use the normal movement multiplier.
 */
void EnforceSlow(int ent, const float org[3], bool isInfectedTeam)
{
	float scale = g_cvWireSlow.FloatValue;

	// Player-controlled infected use the normal movement multiplier plus an optional velocity cap.
	if (ent <= MaxClients)
	{
		if (!isInfectedTeam || scale >= 0.999)
			return;

		float maxSpeed = GetEntPropFloat(ent, Prop_Data, "m_flMaxspeed");
		if (maxSpeed <= 1.0)
			maxSpeed = 300.0;
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

	for (int i = 0; i < 3; i++)
		g_LastPos[ent][i] = newPos[i];
	g_HasLastPos[ent] = true;
}

void ApplySlow(int ent)
{
	float scale = g_cvWireSlow.FloatValue;

	g_Slowed[ent] = true;
	g_AnySlowed   = true;

	if (ent <= MaxClients)
	{
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
	if (ent < 1 || ent > 2048 || !g_Slowed[ent])
		return;

	g_Slowed[ent] = false;

	if (ent <= MaxClients)
	{
		if (IsClientInGame(ent))
			SetEntPropFloat(ent, Prop_Send, "m_flLaggedMovementValue", 1.0);
		return;
	}

	if (!IsValidEntity(ent) || EntIndexToEntRef(ent) != g_TargetRef[ent])
		return;

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
		if (g_Slowed[i])
			ResetSlow(i);
	}
	g_AnySlowed = false;
}