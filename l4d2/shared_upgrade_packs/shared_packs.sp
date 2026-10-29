#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

// m_iClip1 holds PACK_MARK + remaining uses. The offset makes sure a default
// clip value (-1, 0, 1...) is never mistaken for a stored count.
#define PACK_MARK     100
// Stays small in case m_iClip1 is a narrow (8 bit) netprop.
#define MAX_PACK_USES 25

public Plugin myinfo =
{
    name = "Shared Packs",
    author = "Haze_of_dream",
    description = "Allows survivors to share or use upgrade packs with limited uses",
    version = "1.1"
};

bool g_bUseHeld[MAXPLAYERS + 1];
float g_fSelfUseStart[MAXPLAYERS + 1];
bool g_bSelfUseTriggered[MAXPLAYERS + 1];

ConVar g_hEnable;
ConVar g_hUses;
ConVar g_hHoldTime;

// Only used if the pack entity has no m_iClip1 netprop
int g_iFallbackUses[2049];

public void OnPluginStart()
{
    g_hEnable = CreateConVar(
        "sm_sharepack_enable",
        "1",
        "Enable upgrade pack sharing",
        FCVAR_NOTIFY,
        true, 0.0,
        true, 1.0);

    g_hUses = CreateConVar(
        "sm_shared_pack_uses",
        "8",
        "Number of times an upgrade pack can be used before being consumed (max 25)",
        FCVAR_NOTIFY,
        true, 1.0,
        true, float(MAX_PACK_USES));

    g_hHoldTime = CreateConVar(
        "sm_shared_packs_hold_time",
        "0.5",
        "Length of hold required to use your own pack, in seconds",
        FCVAR_NOTIFY,
        true, 0.1);

    AutoExecConfig(true, "shared_packs");
}

public void OnClientDisconnect(int client)
{
    g_bUseHeld[client] = false;
    g_fSelfUseStart[client] = 0.0;
    g_bSelfUseTriggered[client] = false;
}

public void OnEntityDestroyed(int entity)
{
    if (entity > 0 && entity < sizeof(g_iFallbackUses))
    {
        g_iFallbackUses[entity] = 0;
    }
}

public void OnGameFrame()
{
    if (!g_hEnable.BoolValue)
        return;

    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsValidSurvivor(client))
            continue;

        int buttons = GetClientButtons(client);

        if ((buttons & IN_USE) && !g_bUseHeld[client])
        {
            g_bUseHeld[client] = true;
            TryUseUpgradePack(client);
        }
        else if (!(buttons & IN_USE))
        {
            g_bUseHeld[client] = false;
        }

        HandleSelfUse(client, buttons);
    }
}

void HandleSelfUse(int client, int buttons)
{
    bool holding =
        (buttons & IN_SPEED) &&
        (buttons & IN_RELOAD);

    if (!holding)
    {
        g_fSelfUseStart[client] = 0.0;
        g_bSelfUseTriggered[client] = false;
        return;
    }

    if (g_bSelfUseTriggered[client])
        return;

    float gameTime = GetGameTime();

    if (g_fSelfUseStart[client] == 0.0)
    {
        g_fSelfUseStart[client] = gameTime;
        return;
    }

    // FloatValue: IntValue truncated 0.5 to 0 and removed the hold requirement
    if ((gameTime - g_fSelfUseStart[client]) < g_hHoldTime.FloatValue)
        return;

    g_bSelfUseTriggered[client] = true;
    TryUseOwnUpgradePack(client);
}

void TryUseOwnUpgradePack(int client)
{
    UsePack(client, client);
}

void TryUseUpgradePack(int client)
{
    int target = GetClientAimTarget(client, true);

    if (!IsValidSurvivor(target))
        return;

    if (target == client)
        return;

    UsePack(client, target);
}

/**
 * Applies one charge of owner's pack to user.
 * owner == user for self use.
 */
void UsePack(int user, int owner)
{
    int pack = FindPlayerUpgradePack(owner);

    if (pack == -1)
        return;

    char classname[64];
    GetEntityClassname(pack, classname, sizeof(classname));
    bool explosive = StrEqual(classname, "weapon_upgradepack_explosive");

    if (explosive && HasGrenadeLauncher(user))
    {
        PrintToChat(user,
            "\x04[Shared Packs]\x01 Explosive ammo cannot be applied to a grenade launcher.");
        return;
    }

    if (HasUpgradeAmmo(user))
    {
        PrintToChat(user,
            "\x04[Shared Packs]\x01 You already have upgraded ammo loaded.");
        return;
    }

    int remaining = GetOrInitPackUses(pack) - 1;

    GivePlayerUpgrade(user, explosive);

    if (remaining <= 0)
    {
        RemovePlayerItem(owner, pack);
        AcceptEntityInput(pack, "Kill");
    }
    else
    {
        SetPackUses(pack, remaining);
    }

    if (owner == user)
    {
        if (remaining <= 0)
        {
            PrintToChat(user,
                "\x04[Shared Packs]\x01 You used the last charge of your upgrade pack.");
        }
        else
        {
            PrintToChat(user,
                "\x04[Shared Packs]\x01 Upgrade pack uses remaining: %d",
                remaining);
        }

        PrintToChat(user,
            "\x04[Upgrade]\x01 Applied %s ammo to yourself.",
            explosive ? "explosive" : "incendiary");
    }
    else
    {
        if (remaining <= 0)
        {
            PrintToChat(owner,
                "\x04[Shared Packs]\x01 %N used the last charge of your upgrade pack.",
                user);
        }
        else
        {
            PrintToChat(owner,
                "\x04[Shared Packs]\x01 %N used your upgrade pack. Uses remaining: %d",
                user,
                remaining);
        }

        PrintToChat(user,
            "\x04[Shared Packs]\x01 Received %s ammo from %N.",
            explosive ? "explosive" : "incendiary",
            owner);
    }
}

/*=====[ PACK USE STORAGE ]=====*/

// Returns the stored number of remaining uses, or 0 if this pack has none
// stored yet (a fresh pack).
int GetPackUses(int pack)
{
    if (HasEntProp(pack, Prop_Send, "m_iClip1"))
    {
        int raw = GetEntProp(pack, Prop_Send, "m_iClip1");

        if (raw > PACK_MARK && raw <= PACK_MARK + MAX_PACK_USES)
            return raw - PACK_MARK;

        return 0;
    }

    if (pack > 0 && pack < sizeof(g_iFallbackUses))
        return g_iFallbackUses[pack];

    return 0;
}

void SetPackUses(int pack, int uses)
{
    if (HasEntProp(pack, Prop_Send, "m_iClip1"))
    {
        SetEntProp(pack, Prop_Send, "m_iClip1", PACK_MARK + uses);
    }
    else if (pack > 0 && pack < sizeof(g_iFallbackUses))
    {
        g_iFallbackUses[pack] = uses;
    }
}

int GetOrInitPackUses(int pack)
{
    int uses = GetPackUses(pack);

    if (uses <= 0)
    {
        uses = g_hUses.IntValue;
        SetPackUses(pack, uses);
    }

    return uses;
}

/*=====[ HELPERS ]=====*/

// Finds the pack the client is currently carrying in hand. With Multiple
// Equipment, a pack stashed as the 2nd item of the slot is not an entity until
// it is swapped into hand, so it can only be shared after the owner swaps to it.
int FindPlayerUpgradePack(int client)
{
    for (int slot = 0; slot < 5; slot++)
    {
        int weapon = GetPlayerWeaponSlot(client, slot);

        if (weapon <= MaxClients || !IsValidEntity(weapon))
            continue;

        char classname[64];
        GetEntityClassname(weapon, classname, sizeof(classname));

        if (StrEqual(classname, "weapon_upgradepack_incendiary"))
            return weapon;

        if (StrEqual(classname, "weapon_upgradepack_explosive"))
            return weapon;
    }

    return -1;
}

bool HasUpgradeAmmo(int client)
{
    int weapon = GetPlayerWeaponSlot(client, 0);

    if (weapon <= MaxClients || !IsValidEntity(weapon))
        return false;

    if (!HasEntProp(weapon, Prop_Send, "m_nUpgradedPrimaryAmmoLoaded"))
        return false;

    return GetEntProp(weapon, Prop_Send, "m_nUpgradedPrimaryAmmoLoaded") > 0;
}

bool HasGrenadeLauncher(int client)
{
    int weapon = GetPlayerWeaponSlot(client, 0);

    if (weapon <= MaxClients || !IsValidEntity(weapon))
        return false;

    char classname[64];
    GetEntityClassname(weapon, classname, sizeof(classname));

    return StrEqual(classname, "weapon_grenade_launcher");
}

void GivePlayerUpgrade(int client, bool explosive)
{
    int flags = GetCommandFlags("upgrade_add");
    SetCommandFlags("upgrade_add", flags & ~FCVAR_CHEAT);

    if (explosive)
    {
        FakeClientCommand(client, "upgrade_add EXPLOSIVE_AMMO");
    }
    else
    {
        FakeClientCommand(client, "upgrade_add INCENDIARY_AMMO");
    }

    SetCommandFlags("upgrade_add", flags);
}

bool IsValidSurvivor(int client)
{
    return (
        client > 0 &&
        client <= MaxClients &&
        IsClientInGame(client) &&
        IsPlayerAlive(client) &&
        GetClientTeam(client) == 2
    );
}
