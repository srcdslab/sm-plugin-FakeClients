#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

Handle g_hCount;
Handle g_hDelay;
Handle g_hNames;

public Plugin myinfo = {
	name        = "FakeClients",
	author      = "Tsunami",
	description = "Put fake clients in server",
	version     = "2.0.0",
	url         = "http://tsunami-productions.nl"
}

public void OnPluginStart() 
{
	g_hCount = CreateConVar("sm_fakeclients_players", "8",   "Number of players to simulate", _, true, 0.0, true, 64.0);
	g_hDelay = CreateConVar("sm_fakeclients_delay",   "120", "Delay after map change before fake clients join (seconds)", _, true, 0.0, true, 10000.0);
	g_hNames = CreateArray(64);
	AutoExecConfig(true);
}

public void OnMapStart()
{
	ParseNames();
	
	CreateTimer(GetConVarInt(g_hDelay) * 1.0, Timer_CreateFakeClients);
}

public void OnClientPutInServer(int client) 
{
	if(!client)
		return;

	if (!IsFakeClient(client)) 
	{
		/*int iBots = 0, iClients = GetClientCount(true), iMaxBots = GetConVarInt(g_hCount);

		for (int i = 1; i <= MaxClients; i++)
		{
			if (IsClientConnected(i) && IsFakeClient(i))
			{
				iBots++;
			}
		}*/

		for (int i = 1; i <= MaxClients; i++) 
		{
			if (IsClientConnected(i) && IsFakeClient(i))  
			{
				Handle hTVName = FindConVar("tv_name"); 
				char sName[MAX_NAME_LENGTH], sTVName[MAX_NAME_LENGTH];

				GetClientName(i, sName, sizeof(sName));
				
				if (hTVName != INVALID_HANDLE) 
					GetConVarString(hTVName, sTVName, sizeof(sTVName));
				
				if (!StrEqual(sName, sTVName))
				{
					KickClient(i, "Slot reserved");
					break;
				}
			}
		}
	}
}

public void OnClientDisconnect(int client)
{
	CreateTimer(1.0, Timer_CreateFakeClient);
}

public Action Timer_CreateFakeClient(Handle timer)
{
	int iBots = 0, iClients = GetClientCount(true), iMaxBots = GetConVarInt(g_hCount);
	
	if (iClients < MaxClients) 
	{
		for (int i = 1; i <= MaxClients; i++)
		{
			if (IsClientConnected(i) && IsFakeClient(i))
			{
				iBots++;
			}
		}
		
		if (iBots < iMaxBots && iClients < iMaxBots) 
		{
			char sTarget[MAX_TARGET_LENGTH];
			char sName[MAX_NAME_LENGTH];
			int iTargets[MAXPLAYERS];
			bool bTN_Is_ML;
			GetArrayString(g_hNames, GetRandomInt(0, GetArraySize(g_hNames) - 1), sName, sizeof(sName));
			
			while (ProcessTargetString(sName,
			                           0,
			                           iTargets,
			                           MAXPLAYERS,
			                           COMMAND_FILTER_NO_MULTI,
			                           sTarget,
			                           MAX_TARGET_LENGTH,
			                           bTN_Is_ML) == 1 && IsFakeClient(iTargets[0])) 
			{
				GetArrayString(g_hNames, GetRandomInt(0, GetArraySize(g_hNames) - 1), sName, sizeof(sName));
			}
			
			CreateFakeClient(sName);
		}
	}
	
	return Plugin_Handled;
}

public Action Timer_CreateFakeClients(Handle timer) 
{
	for (int i = 1, c = GetConVarInt(g_hCount); i <= c; i++) 
	{
		CreateTimer(i * 1.0, Timer_CreateFakeClient);
	}

	return Plugin_Continue;
}

stock void ParseNames() 
{
	char sBuffer[256];
	BuildPath(Path_SM, sBuffer, sizeof(sBuffer), "configs/fakeclients.txt");
	
	Handle hConfig = OpenFile(sBuffer, "r");
	
	if (hConfig != INVALID_HANDLE) 
	{
		ClearArray(g_hNames);
		
		while (ReadFileLine(hConfig, sBuffer, sizeof(sBuffer)))
		{
			TrimString(sBuffer);
			
			if (strlen(sBuffer) > 0) 
			{
				PushArrayString(g_hNames, sBuffer);
			}
		}
		
		CloseHandle(hConfig);
	}
}
