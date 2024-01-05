#include <sourcemod>
#include <sdktools>

#pragma semicolon 1

#define PL_VERSION "2.0.7"
#define UNDEFINED 0
#define RED_TEAM 2
#define BLU_TEAM 3

// Constants
#define VOTEINFO_ITEM_INDEX     0       // Item index
#define VOTEINFO_ITEM_VOTES     1       // Number of votes for the item 
#define NUM_ROUNDS              3       // Number of rounds scoreHistory looks back on
#define COOLDOWN_DURATION      300      // Cooldown for a new fgm vote to be called


// Global variables
new bool:gFGMEnabled = false;           // Indicates whether FGM game mode is enabled
int gLastVoteTime = 0;                  // Stores the timestamp of the last FGM vote initiation
int winningTeam = UNDEFINED;            // Indicates which team is winning team
int lastWinner = UNDEFINED;             // Indicates which team won the previous round
int gConsecutiveWins = 0;               // Counts the number of times the same team has won

enum struct PlayerData
{
    int totalScore;
    int queuePointer;
    int scoreQueue[NUM_ROUNDS];
}

void initializePlayerData(PlayerData data)
{
    data.totalScore = 1;
    data.queuePointer = 2;
    for (int i = 0; i < NUM_ROUNDS; i++)
    {
        data.scoreQueue[i] = i;
    }
}

PlayerData scoreHistory[MAXPLAYERS+1]; // Array keeping track of player scores with client ids used as indexes

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

public void OnClientAuthorized(int client)
{
    // Initialize a player data
    PlayerData data;
    initializePlayerData(data);
    PrintToServer("totalScore: %d\nqueuePointer: %d\nscoreQueue[0]: %d\nscoreQueue[1]: %d, scoreQueue[2]: %d\n", data.totalScore, data.queuePointer, data.scoreQueue[0], data.scoreQueue[1], data.scoreQueue[2]);

    // Initialize set client user
    scoreHistory[client] = data;
}

// Disable FGM if it's enabled when a map ends, resetting it.
public void OnMapEnd()
{
    if (gFGMEnabled)
    {
        DisableFGM();
    }
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
    int yes_votes;
    int no_votes;

    // There are no items, nobody voted
    if (num_items == 0)
    {
        PrintToChatAll("[FewGoodMen] Vote failed, no votes were made.");
        return;
    }
    else if (num_items == 1) // There is only one item, only one option was voted for.
    {
        int idx = item_info[0][VOTEINFO_ITEM_INDEX];
        if (idx == 0)
        {
            // Yes votes won.
            yes_votes = 1;
            no_votes = 0;
        }
        else
        {
            // No votes won.
            yes_votes = 0;
            no_votes = 1;
        }
    }
    else // Both options were voted for.
    {
        yes_votes = item_info[0][VOTEINFO_ITEM_VOTES];
        no_votes = item_info[1][VOTEINFO_ITEM_VOTES];
    }
        
    if (yes_votes > no_votes)
    {
        // FGM was already enabled
        if (gFGMEnabled == true)
        {
            PrintToChatAll("[FewGoodMen] Vote to disable fgm failed.");
        }
        else // FGM is disabled
        {
            EnableFGM();    
            PrintToChatAll("[FewGoodMen] Vote to enable fgm succeeded.");
        }
    }
    else if (yes_votes < no_votes)
    {
        // FGM is enabled
        if (gFGMEnabled == true)
        {
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

public EnableFGM()
{
    gFGMEnabled = true;
    winningTeam = UNDEFINED;
    gConsecutiveWins = 0;
    // Start paying attention to round wins
    HookEvent("teamplay_round_win", OnRoundWin);
    HookEvent("teamplay_round_start", OnRoundStart);
    HookEvent("player_team", HookPlayerChangeTeam);
    // Disable autobalance so we don't have problems
    ServerCommand("mp_autoteambalance 0");
}

public DisableFGM()
{
    gFGMEnabled = false;
    // Stop paying attention to round wins
    UnhookEvent("teamplay_round_win", OnRoundWin);
    UnhookEvent("teamplay_round_start", OnRoundStart);
    UnhookEvent("player_team", HookPlayerChangeTeam);
    // Re-enable autobalance
    ServerCommand("mp_autoteambalance 1");
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
    // Make sure either team won
    if (winner == BLU_TEAM || winner == RED_TEAM)
    {
        HandleWinningTeam(winner);
    }

    return Plugin_Handled;
}

public HandleWinningTeam(int latestWinner)
{
    if (winningTeam != UNDEFINED)
    {
        // There is a consecutive winner
        if (latestWinner == winningTeam)
        {
            // The consecutive winner won again
            gConsecutiveWins = gConsecutiveWins + 1;
        }
        else
        {
            // The consecutive winner lost
            if (gConsecutiveWins == 0)
            {
                // The consecutive winner lost twice in a row
                winningTeam = 3 - latestWinner;
                gConsecutiveWins = 2;
            }
            else
            {
                // The consecutive winner lost once
                gConsecutiveWins = 0;
                return;
            }
        }
    }
    else
    {
        // There isn't a consecutive winner
        if (gConsecutiveWins == 0)
        {
            gConsecutiveWins = 1;
            lastWinner = latestWinner;
            return;
        }
        else if (lastWinner == latestWinner)
        {
            gConsecutiveWins = 2;
            winningTeam = latestWinner;
        }
        else
        {
            
        }
    }

    // Evaluate gConsecutiveWins
    if (winningTeam == RED_TEAM)
    {
        // RED team won
        PrintToChatAll("[FewGoodMen] RED team has %d straight wins!", gConsecutiveWins);
    }
    else if (winningTeam == BLU_TEAM)
    {
        // BLU team won
        PrintToChatAll("[FewGoodMen] BLU team has %d straight wins!", gConsecutiveWins);
    }
}


// Round start event handler
public Action:OnRoundStart(Event:event, const char[] name, bool dontBroadcast)
{
    // Evaluate gConsecutiveWins. Don't do anything if no consecutive wins.
    if (gConsecutiveWins > 2)
    {
        // Get the least contributing team member of the losing team
        int worstContributor = GetLowestScoreOnWinningTeam();
        if (worstContributor != -1)
        {
            ForcePlayerToLosingTeam(worstContributor);
            PrintToChatAll("[FewGoodMen] Moving a player to the losing team.");
        }
    }
    
    return Plugin_Handled;
}


public ForcePlayerToLosingTeam(int client)
{
    // If RED is winning, move them to BLU
    if (winningTeam == RED_TEAM)
    {
        ChangeClientTeam(client, 3);
    }
    else // Otherwise move them to RED
    {
        ChangeClientTeam(client, 2);
    }
}

// TODO: 
// If data is less than 3 rounds, use current score
public int GetLowestScoreOnWinningTeam()
{
    
    int clientID;
    return clientID;
}

// Get score of client from client_id
public int GetPlayerResourceTotalScore(int client)
{
    int playerSourceEnt = GetPlayerResourceEntity();
    return GetEntProp(playerSourceEnt, Prop_Send, "m_iTotalScore", _, client);
}

// TODO: If player attempts to change teams to winning team, send them to losing team
// no message if no swap
public Action:HookPlayerChangeTeam(Event:event, const char[] name, bool dontBroadcast)
{
    // void ChangeClientTeam(int client, int team);
    return Plugin_Handled;
}

