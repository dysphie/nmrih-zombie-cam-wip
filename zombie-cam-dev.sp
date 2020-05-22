// TODO: 
// Too many things

#include <sdktools>
#include <sdkhooks>
#include <sourcemod>

#pragma semicolon 1
#pragma newdecls required

#define MAXPLAYERS_NMRIH 9

ArrayList g_hZombies;

enum struct ZombieCamera
{
	// Ent ref to our camera prop
	int camera;

	// Current position in g_hZombies
	int cursor;

	// Return the entity index of the dummy prop we use as our cam
	int GetCamera()
	{
		if(!this.camera)
			return -1;

		return EntRefToEntIndex(this.camera);
	}

	// Attach our camera to a zombie's eyes
	void Attach(int zombie)
	{
		int camera = this.GetCamera();

		if(camera == -1)
		{
			PrintToServer("ERROR: ZombieCamera.Attach() called with no camera");
			return;
		}

		AcceptEntityInput(camera, "ClearParent");

		SetVariantString("!activator");
		AcceptEntityInput(camera, "SetParent", zombie);

		SetVariantString("headshot_squirt");
		AcceptEntityInput(camera, "SetParentAttachment");

		float vecAngles[3];
		GetEntPropVector(camera, Prop_Send, "m_angRotation", vecAngles);

		// FIXME: Wrong orientation for zombie children
		// TODO: Proper correction based on model names
		vecAngles[1] += 270.0;
		vecAngles[2] = 0.0;

		SetEntPropVector(camera, Prop_Send, "m_angRotation", vecAngles);
	}

	bool Create()
	{
		if(this.GetCamera() != -1)
		{
			PrintToServer("WARNING: ZombieCamera.Create() called but camera already present. Ignoring");
			return true;
		}

		// Don't create the camera if we have nothing to attach it to
		if(!g_hZombies.Length)
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

		int zombie = g_hZombies.Get(0);
		this.Attach(zombie);
		return true;
	}

	void Delete()
	{
		int camera = this.GetCamera();

		if(camera != -1)
			RemoveEntity(camera);

		this.cursor = 0;
	}

	bool Next()
	{
		if(this.GetCamera() == -1)
		{
			PrintToServer("ERROR: ZombieCamera.Next() called with no camera");
			return false;
		}

		int len = g_hZombies.Length;
		if(!len)
		{
			PrintToServer("ERROR: ZombieCamera.Next() called but no zombies present");
			return false;
		}

		this.cursor = (this.cursor + 1) % len;
		int zombie = g_hZombies.Get(this.cursor);
		this.Attach(zombie);
		PrintToServer("Cursor at %d", this.cursor);

		return true;
	}

	bool Prev()
	{
		if(this.GetCamera() == -1)
		{
			PrintToServer("ERROR: ZombieCamera.Prev() called with no camera");
			return false;
		}

		int len = g_hZombies.Length;
		if(!len)
		{
			PrintToServer("ERROR: ZombieCamera.Prev() called but no zombies present");
			return false;
		}

		this.cursor = (this.cursor + (len - 1)) % len;
		int zombie = g_hZombies.Get(this.cursor);
		this.Attach(zombie);
		PrintToServer("Cursor at %d", this.cursor);

		return true;
	}

	// Get the zombie we are currently spectating
	int GetTargetZombie()
	{
		if(this.GetCamera() == -1)
			return -1;

		return GetEntPropEnt(this.camera, Prop_Data, "m_hMoveParent");
	}
}

ZombieCamera g_ZombieCameras[MAXPLAYERS_NMRIH+1];

public void OnPluginStart()
{
	g_hZombies = new ArrayList();

	RegConsoleCmd("sm_spec", OnCmdSpec);
	RegConsoleCmd("sm_exit", OnCmdExit);
	RegConsoleCmd("sm_next", OnCmdNext);
	RegConsoleCmd("sm_prev", OnCmdPrev);

	// Late load handling
	int i = -1; 
	while((i = FindEntityByClassname(i, "npc_nmrih*")) != -1)
		g_hZombies.Push(i);
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if(IsEntityZombie(entity))
		g_hZombies.Push(entity);
}

public void OnEntityDestroyed(int entity)
{
	if(!IsEntityZombie(entity))
		return;

	int idx = g_hZombies.FindValue(entity);
	g_hZombies.Erase(idx);

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
	int camera;
	for(int i = 1; i <= MaxClients; i++)
	{
		if(!IsClientInGame(i))
			continue;

		camera = g_ZombieCameras[i].GetCamera();
		if(camera == -1)
			continue;

		RemoveEntity(g_ZombieCameras[i].camera);
		SetClientViewEntity(i, i);
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
