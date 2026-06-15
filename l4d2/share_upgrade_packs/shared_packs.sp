#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

public Plugin myinfo =
{
    name = "Shared Packs",
    author = "Haze_of_dream",
    description = "Allows survivors to share or use upgrade packs with limited uses",
    version = "1.0"
};

bool g_bUseHeld[MAXPLAYERS + 1];

float g_fSelfUseStart[MAXPLAYERS + 1];
bool g_bSelfUseTriggered[MAXPLAYERS + 1];

ConVar g_hEnable;
ConVar g_hUses;
ConVar g_hHoldTime;

int g_iPackUses[2049];

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
        "Number of times an upgrade pack can be used before being consumed",
        FCVAR_NOTIFY,
        true, 1.0);

    g_hHoldTime = CreateConVar(
        "sm_shared_packs_hold_time",
        "0.5",
        "Length of hold required to use your own pack",
        FCVAR_NOTIFY,
        false, 0.1);

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
    if (entity > 0 && entity < sizeof(g_iPackUses))
    {
        g_iPackUses[entity] = 0;
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

    if ((gameTime - g_fSelfUseStart[client]) < g_hHoldTime.IntValue)
        return;

    g_bSelfUseTriggered[client] = true;

    TryUseOwnUpgradePack(client);
}

void TryUseOwnUpgradePack(int client)
{
    int pack = FindPlayerUpgradePack(client);

    if (pack == -1)
        return;

    InitializePackUses(pack);

    char classname[64];
    GetEntityClassname(pack, classname, sizeof(classname));

    bool explosive = StrEqual(classname, "weapon_upgradepack_explosive");

    if (explosive && HasGrenadeLauncher(client))
    {
        PrintToChat(client,
            "\x04[Shared Packs]\x01 Explosive ammo cannot be applied to a grenade launcher.");
        return;
    }

    if (HasUpgradeAmmo(client))
    {
        PrintToChat(client,
            "\x04[Shared Packs]\x01 You already have upgraded ammo loaded.");
        return;
    }

    GivePlayerUpgrade(client, explosive);

    g_iPackUses[pack]--;

    if (g_iPackUses[pack] <= 0)
    {
        RemovePlayerItem(client, pack);
        AcceptEntityInput(pack, "Kill");

        PrintToChat(client,
            "\x04[Shared Packs]\x01 Your upgrade pack has been depleted.");
    }
    else
    {
        PrintToChat(client,
            "\x04[Upgrade]\x01 Upgrade pack uses remaining: %d",
            g_iPackUses[pack]);
    }

    PrintToChat(client,
        "\x04[Upgrade]\x01 Applied %s ammo to yourself.",
        explosive ? "explosive" : "incendiary");
}

void TryUseUpgradePack(int client)
{
    int target = GetClientAimTarget(client, true);

    if (!IsValidSurvivor(target))
        return;

    if (target == client)
        return;

    int pack = FindPlayerUpgradePack(target);

    if (pack == -1)
        return;

    InitializePackUses(pack);

    char classname[64];
    GetEntityClassname(pack, classname, sizeof(classname));

    bool explosive = StrEqual(classname, "weapon_upgradepack_explosive");

    if (explosive && HasGrenadeLauncher(client))
    {
        PrintToChat(client,
            "\x04[Shared Packs]\x01 Explosive ammo cannot be applied to a grenade launcher.");
        return;
    }

    if (HasUpgradeAmmo(client))
    {
        PrintToChat(client,
            "\x04[Shared Packs]\x01 You already have upgraded ammo loaded.");
        return;
    }

    GivePlayerUpgrade(client, explosive);

    g_iPackUses[pack]--;

    if (g_iPackUses[pack] <= 0)
    {
        RemovePlayerItem(target, pack);
        AcceptEntityInput(pack, "Kill");

        PrintToChat(
            target,
            "\x04[Shared Packs]\x01 %N used the last charge of your upgrade pack.",
            client
        );
    }
    else
    {
        PrintToChat(
            target,
            "\x04[Shared Packs]\x01 %N used your upgrade pack. Uses remaining: %d",
            client,
            g_iPackUses[pack]
        );
    }

void InitializePackUses(int pack)
{
    if (pack <= MaxClients || !IsValidEntity(pack))
        return;

    if (g_iPackUses[pack] <= 0)
    {
        g_iPackUses[pack] = g_hUses.IntValue;
    }
}

int FindPlayerUpgradePack(int client)
{
    for (int slot = 0; slot < 6; slot++)
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