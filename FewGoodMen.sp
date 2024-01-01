#include <sourcemod>
#include <sdktools.inc>

#pragma semicolon 1

#define PL_VERSION "2.0.4"
// Constants
new const Float:COOLDOWN_DURATION = 300.0; // 5 minutes cooldown in seconds

// Global variables
new bool:gFGMEnabled = false;  // Indicates whether FGM game mode is enabled
int gLastVoteTime = 0;  // Stores the timestamp of the last FGM vote initiation
new bool:gRedWinning = false; // Indicates whether RED team is winning (BLU is winning if false)
new bool:gFirstRound = true; // Indicates whether it is the first round after enabling FGM
int gConsecutiveWins = 0; // Counts the number times the same team has won

// Function prototypes
public Action:OnFGMCommand(int client, int args);
public Action:OnDFGMCommand(int client, int args);
public StartVote();
public VoteResult(Menu menu, int num_votes, int num_clients, const int[][] client_info, int num_items, const int[][] item_info);
public HandleVoteMenu(Menu:menu, MenuAction:action, param1, param2);
public Action:OnPlayerSpawn(Handle:event, const String:name[], bool:dontBroadcast);
public Action:OnRoundWin(Event:event, const String:name[], bool:dontBroadcast);
public Action:HookPlayerChangeTeam(Event:event, const char[] name, bool dontBroadcast);



// Main plugin information
public Plugin:myinfo = 
{
    name = "FGM Plugin",
    author = "kookie",
    description = "Implements FGM game mode with voting",
    version = PL_VERSION,
    url = "https://www.disc-ff.com"
};

// Plugin initialization
public void OnPluginStart()
{
    RegConsoleCmd("sm_fgm", OnFGMCommand, "Starts the vote to enable FGM");
    RegConsoleCmd("sm_dfgm", OnDFGMCommand, "Starts the vote to disable FGM");
    RegConsoleCmd("sm_disablefgm", OnDFGMCommand, "Starts the vote to disable FGM");
}

// FGM command handler
public Action:OnFGMCommand(int client, int args)
{
    if (gFGMEnabled == true)
    {
        PrintToChat(client, "FewGoodMen is already enabled. Start a vote to disable it with /dfgm");
    }
    else if (IsVoteInProgress())
    {
        PrintToChat(client, "Another vote is currently in progress.");
    }
    else if ((GetTime() - gLastVoteTime) < COOLDOWN_DURATION)
    {
        PrintToChat(client, "[FewGoodMen] You must wait %d seconds before initiating another vote.", COOLDOWN_DURATION - GetTime() + gLastVoteTime);
    }
    else // If no vote is in progress, and it is past the cooldown time, start the vote.
    {
        gLastVoteTime = GetTime();
        StartVote();
    }
    return Plugin_Handled;
}

// DFGM command handler
public Action:OnDFGMCommand(int client, int args)
{
    if (gFGMEnabled == false)
    {
        PrintToChat(client, "FewGoodMen is already disabled. Start a vote to enable it with /fgm");
    }
    else if (IsVoteInProgress())
    {
        PrintToChat(client, "Another vote is currently in progress.");
    }
    else if ((GetTime() - gLastVoteTime) < COOLDOWN_DURATION)
    {
        PrintToChat(client, "[FewGoodMen] You must wait %d seconds before initiating another vote.", COOLDOWN_DURATION - GetTime() + gLastVoteTime);
    }
    else // If no vote is in progress, and it is past the cooldown time, start the vote.
    {
        gLastVoteTime = GetTime();
        StartVote();
    }
    return Plugin_Handled;
}

// Start the FGM vote
public StartVote()
{
    new Menu:menu = CreateMenu(HandleVoteMenu);
    SetMenuTitle(menu, "Enable Few Good Men?");
    AddMenuItem(menu, "yes", "Yes");
    AddMenuItem(menu, "no", "No");
    SetMenuExitButton(menu, false);
    SetVoteResultCallback(menu, VoteResult);
    VoteMenuToAll(menu, 15);
}

// Done to make sure ties result in status quo, and not random chance.
public VoteResult(Menu:menu, int num_votes, int num_clients, const int[][] client_info, int num_items, const int[][] item_info)
{
    int yes_votes = item_info[0][1];
    int no_votes = item_info[1][1];

    if (yes_votes > no_votes)
    {
        // FGM was already enabled
        if (gFGMEnabled == true)
        {
            PrintToChatAll("[FewGoodMen] Vote to disable fgm failed.");
        }
        else // FGM is disabled
        {
            gFGMEnabled = true;
            // Start paying attention to round wins
            HookEvent("teamplay_round_win", OnRoundWin);
            HookEvent("teamplay_round_start", OnRoundStart);
            HookEvent("player_team", HookPlayerChangeTeam);
            PrintToChatAll("[FewGoodMen] Vote to enable fgm succeeded.");
        }
    }
    else if (no_votes > yes_votes)
    {
        // FGM is enabled
        if (gFGMEnabled == true)
        {
            gFGMEnabled = false;
            gConsecutiveWins = 0;
            gRedWinning = false;
            gFirstRound = true;
            // Stop paying attention to round wins
            UnhookEvent("teamplay_round_win", OnRoundWin);
            UnhookEvent("teamplay_round_start", OnRoundStart);
            UnhookEvent("player_team", HookPlayerChangeTeam);
            PrintToChatAll("[FewGoodMen] Vote to disable fgm succeeded.");
        }
        else // FGM is already disabled
        {
            PrintToChatAll("[FewGoodMen] Vote to enable fgm failed.");
        }
    }
    else if (yes_votes == no_votes)
    {
        // FGM is enabled
        if (gFGMEnabled == true)
        {
            PrintToChatAll("[FewGoodMen] Vote to disable fgm failed.");
        }
        else // FGM is disabled
        {
            PrintToChatAll("[FewGoodMen] Vote to enable fgm failed.");
        }
    }
}

public HandleVoteMenu(Menu:menu, MenuAction:action, param1, param2)
{
	if (action == MenuAction_End)
	{
		/* This is called after VoteResult */
		CloseHandle(menu);
	}
}


// Round win event handler
public Action:OnRoundWin(Event:event, const char[] name, bool dontBroadcast)
{
    int winner = event.GetInt("team");
    // RED = 2, BLU = 3
    if (winner == 2)
    {
        HandleWinningTeam(true);
    }
    else if (winner == 3)
    {
        HandleWinningTeam(false);
    }
    else
    {
        // Stalemate occurred. Do nothing. Don't update gFirstRound.
        return Plugin_Handled;
    }

    if (gFirstRound == true)
    {
        // The first round has passed
        gFirstRound = false;
    }
    return Plugin_Handled;
}

public HandleWinningTeam(bool latestWinner)
{
    // The winning team won last round
    if (gRedWinning == latestWinner)
    {
        // No need to set gRedWinning, it did not change.
        // Increment gConsecutiveWins by 1
        gConsecutiveWins = gConsecutiveWins + 1;
    }
    else // The winning team lost last round
    {
        // Did it lose twice in a row? Or did RED team win the first round after /fgm?
        if (gConsecutiveWins == 0)
        {
            // The losing team won twice in a row or RED team won the first round
            // The losing team becomes the winning team 
            gRedWinning = !gRedWinning;
            // Is it the first round after /fgm?
            if (gFirstRound == true)
            {
                // They've only won once
                gConsecutiveWins = 1;
            }
            else
            {
                // The now winning team has won twice in a row
                gConsecutiveWins = 2;
            } 
        }
        else
        {
            // The winning team lost its streak
            gConsecutiveWins = 0;
        }
    }

    // Evaluate gConsecutiveWins
    if (gConsecutiveWins > 1)
    {
        if (gRedWinning)
        {
            PrintToChatAll("[FewGoodMen] RED team has %d straight wins!", gConsecutiveWins);
        }
        else
        {
            PrintToChatAll("[FewGoodMen] BLU team has %d straight wins!", gConsecutiveWins);
        }
    }
}


// Round start event handler
public Action:OnRoundStart(Event:event, const char[] name, bool dontBroadcast)
{
    // Evaluate gConsecutiveWins. Don't do anything if no consecutive wins.
    if (gConsecutiveWins < 2)
    {
        return Plugin_Handled;
    }

    // Get the least contributing team member of the losing team
    int worstContributor = GetLowestScoreOnWinningTeam();
    return Plugin_Handled;
}


public ForcePlayerToLosingTeam(int client)
{
    if (client == -1)
    {
        // GetLowestScoreOnWinningTeam() returned -1, don't force player to losing team.
        return;
    }
    // If RED is winning, move them to BLU
    if (gRedWinning)
    {
        ChangeClientTeam(client, 3);
    }
    else // Otherwise move them to RED
    {
        ChangeClientTeam(client, 2);
    }
}

// TODO: 
public int GetLowestScoreOnWinningTeam()
{
    // Return client_id of lowest scorer? Save scores every end of round?
    // Implement some failsafe so people don't get ping ponged?
}


public int GetPlayerResourceTotalScore(int client)
{
    int playerSourceEnt = GetPlayerResourceEntity();
    return GetEntProp(playerSourceEnt, Prop_Send, "m_iTotalScore", _, client);
}

// TODO: If player attempts to change teams to winning team, send them to losing team
// no message if no swap
// swap message: [FewGoodMen] Moving a player to the losing team.
// swap at the beginning of next round
public Action:HookPlayerChangeTeam(Event:event, const char[] name, bool dontBroadcast)
{
    return Plugin_Handled;
}