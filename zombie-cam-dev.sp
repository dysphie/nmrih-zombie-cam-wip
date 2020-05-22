// TODO: 
// Too many things

#include <sdktools>
#include <sdkhooks>
#include <sourcemod>

#pragma semicolon 1
#pragma newdecls required

#define MAXPLAYERS_NMRIH 9

ArrayList g_Zombies;

enum struct ZombieCamera
{
	// Ent ref to our camera prop
	int camera;

	// Current position in g_Zombies
	int cursor;

	// TODO: Replace this function for GetCamera
	bool IsValid()
	{
		return this.camera && EntRefToEntIndex(this.camera) != -1;
	}

	// Attach our camera to a zombie's eyes
	void Attach(int zombie)
	{
		if(!this.IsValid())
		{
			PrintToServer("ERROR: ZombieCamera.Attach() called with no camera");
			return;
		}

		AcceptEntityInput(this.camera, "ClearParent");

		SetVariantString("!activator");
		AcceptEntityInput(this.camera, "SetParent", zombie);

		SetVariantString("headshot_squirt");
		AcceptEntityInput(this.camera, "SetParentAttachment");

		float vecAngles[3];
		GetEntPropVector(this.camera, Prop_Send, "m_angRotation", vecAngles);

		// FIXME: Wrong orientation for zombie children
		// TODO: Proper correction based on model names
		vecAngles[1] += 270.0;
		vecAngles[2] = 0.0;

		SetEntPropVector(this.camera, Prop_Send, "m_angRotation", vecAngles);
	}

	bool Create()
	{
		if(this.IsValid())
		{
			PrintToServer("WARNING: ZombieCamera.Create() called but camera already present. Ignoring");
			return true;
		}

		// Don't create the camera if we have nothing to attach it to
		if(!g_Zombies.Length)
		{
			PrintToServer("WARNING: ZombieCamera.Create() called but no zombies present");
			return false;
		}

		// Is there a better way of doing this? Maybe, too bad!
		int camera = CreateEntityByName("prop_dynamic_override");
		DispatchKeyValue(camera, "model", "models/blackout.mdl");
		DispatchKeyValue(camera, "spawnflags", "256");
		DispatchKeyValue(camera, "rendermode", "10");
		DispatchKeyValue(camera, "solid", "0");
		DispatchSpawn(camera);

		this.camera = EntIndexToEntRef(camera);

		int zombie = g_Zombies.Get(0);
		this.Attach(zombie);
		return true;
	}

	void Delete()
	{
		if(!this.IsValid())
			return;

		RemoveEntity(this.camera);
	}

	bool Next()
	{
		if(!this.IsValid())
		{
			PrintToServer("ERROR: ZombieCamera.Next() called with no camera");
			return false;
		}

		int len = g_Zombies.Length;
		if(!len)
		{
			PrintToServer("ERROR: ZombieCamera.Next() called but no zombies present");
			return false;
		}

		this.cursor = (this.cursor + 1) % len;
		int zombie = g_Zombies.Get(this.cursor);
		this.Attach(zombie);
		PrintToServer("Cursor at %d", this.cursor);

		return true;
	}

	bool Prev()
	{
		if(!this.IsValid())
		{
			PrintToServer("ERROR: ZombieCamera.Prev() called with no camera");
			return false;
		}

		int len = g_Zombies.Length;
		if(!len)
		{
			PrintToServer("ERROR: ZombieCamera.Prev() called but no zombies present");
			return false;
		}

		this.cursor = (this.cursor + (len - 1)) % len;
		int zombie = g_Zombies.Get(this.cursor);
		this.Attach(zombie);
		PrintToServer("Cursor at %d", this.cursor);

		return true;
	}

	// Get the zombie we are currently spectating
	int GetTargetZombie()
	{
		if(!this.IsValid())
			return -1;

		return GetEntPropEnt(this.camera, Prop_Data, "m_hMoveParent");
	}
}

ZombieCamera g_ZombieCameras[MAXPLAYERS_NMRIH+1];

public void OnPluginStart()
{
	g_Zombies = new ArrayList();

	RegConsoleCmd("sm_spec", OnCmdSpec);
	RegConsoleCmd("sm_exit", OnCmdExit);
	RegConsoleCmd("sm_next", OnCmdNext);
	RegConsoleCmd("sm_prev", OnCmdPrev);

	// Late load handling
	int i = -1; 
	while((i = FindEntityByClassname(i, "npc_nmrih*")) != -1)
		g_Zombies.Push(i);
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if(IsEntityZombie(entity))
		g_Zombies.Push(entity);
}

public void OnEntityDestroyed(int entity)
{
	if(!IsEntityZombie(entity))
		return;

	int idx = g_Zombies.FindValue(entity);
	g_Zombies.Erase(idx);

	for(int i = 1; i <= MaxClients; i++)
	{
		if(!IsClientInGame(i) /* || IsPlayerAlive(i) */)
			continue;

		if(g_ZombieCameras[i].GetTargetZombie() != entity)
			continue;

		PrintToServer("Zombie being spectated deleted, moving client");

		if(!g_ZombieCameras[i].Next())
			SetClientViewEntity(i, i);
	}
}

public void OnClientDisconnected(int client)
{
	g_ZombieCameras[client].Delete();
}

stock bool IsEntityZombie(int entity)
{
	return HasEntProp(entity, Prop_Send, "_headSplit");
}

// Dev cmds
public Action OnCmdSpec(int client, int args)
{
	g_ZombieCameras[client].Create();
	SetClientViewEntity(client, g_ZombieCameras[client].camera);
	return Plugin_Handled;
}

public Action OnCmdNext(int client, int args)
{
	g_ZombieCameras[client].Next();
	return Plugin_Handled;
}

public Action OnCmdPrev(int client, int args)
{
	g_ZombieCameras[client].Prev();
	return Plugin_Handled;
}

public Action OnCmdExit(int client, int args)
{
	g_ZombieCameras[client].Delete();
	return Plugin_Handled;
}

public void OnPluginEnd()
{
	for(int i = 1; i <= MaxClients; i++)
	{
		if(g_ZombieCameras[i].IsValid())
		{
			RemoveEntity(g_ZombieCameras[i].camera);
			SetClientViewEntity(i, i);
		}
	}
}

public void OnPlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(!client)
		return;

	SetClientViewEntity(client, client);
	g_ZombieCameras[client].Delete();
}

stock void GetCorrectionsForModel(const char modelName, float origin[3], float angles[3])
{

}
