#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>

public Plugin myinfo =
{
    name        = "M16 Reserve Ammo",
    author      = "Haze_of_dream",
    description = "Increases M16 (assault rifle) reserve ammo cap",
    version     = "1.0"
};

ConVar g_cvRifleAmmo;

public void OnPluginStart()
{
    g_cvRifleAmmo = FindConVar("ammo_assaultrifle_max");

    if (g_cvRifleAmmo == null)
    {
        SetFailState("ConVar ammo_assaultrifle_max not found");
        return;
    }

    // Set immediately
    g_cvRifleAmmo.SetInt(500);

    // Optional: lock it so other plugins / configs don't override it
    g_cvRifleAmmo.AddChangeHook(OnAmmoChanged);
}

public void OnAmmoChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    // Enforce value
    if (convar.IntValue != 500)
    {
        convar.SetInt(500);
    }
}