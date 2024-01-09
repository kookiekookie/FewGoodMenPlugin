#include <sourcemod>
#include <sdktools>

#pragma semicolon 1

#define PL_VERSION "2.2.0"
#define UNDEFINED 0
#define RED_TEAM 2
#define BLU_TEAM 3

// Constants
#define VOTEINFO_ITEM_INDEX     0       // Item index
#define VOTEINFO_ITEM_VOTES     1       // Number of votes for the item 
#define NUM_ROUNDS              3       // Number of rounds scoreHistory looks back on
#define COOLDOWN_DURATION      180     // Cooldown for a new fgm vote to be called


// Global variables
new bool:gFGMEnabled = false;           // Indicates whether FGM game mode is enabled
int gLastVoteTime = 0;                  // Stores the timestamp of the last FGM vote initiation
int winningTeam = UNDEFINED;            // Indicates which team is winning team
int lastWinner = UNDEFINED;             // Indicates which team won the previous round
int gConsecutiveWins = 0;               // Counts the number of times the same team has won

enum struct PlayerData
{
    int currentScore;
    int queuePointer;
    int scoreQueue[NUM_ROUNDS];
    int scoreTotalDelta;
    bool useCurrentScore;
}

void initializePlayerData(PlayerData data)
{
    data.currentScore = 0;
    data.queuePointer = 0;
    for (int i = 0; i < NUM_ROUNDS; i++)
    {
        data.scoreQueue[i] = i;
    }
    data.scoreTotalDelta = 0;
    data.useCurrentScore = true;
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
public OnPluginStart()
{
    RegConsoleCmd("sm_fgm", OnFGMCommand, "Starts the vote to enable FGM");
    RegConsoleCmd("sm_dfgm", OnDFGMCommand, "Starts the vote to disable FGM");
    RegConsoleCmd("sm_disablefgm", OnDFGMCommand, "Starts the vote to disable FGM");
}

public OnClientAuthorized(int client)
{
    // Initialize a player data
    PlayerData data;
    initializePlayerData(data);

    // Initialize set client user
    scoreHistory[client] = data;
}

// Disable FGM if it's enabled when a map ends, thereby resetting it.
public OnMapEnd()
{
    gLastVoteTime = 0;
    if (gFGMEnabled)
    {
        DisableFGM();
    }
}



// FGM command handler
Action:OnFGMCommand(int client, int args)
{
    if (gFGMEnabled == true)
    {
        PrintToChat(client, "FewGoodMen is already enabled. Start a vote to disable it with /dfgm");
    }
    else if ((GetTime() - gLastVoteTime) < COOLDOWN_DURATION)
    {
        PrintToChat(client, "[FewGoodMen] You must wait %d seconds before initiating another vote.", COOLDOWN_DURATION - GetTime() + gLastVoteTime);
    }
    else if (IsVoteInProgress())
    {
        PrintToChat(client, "Another vote is currently in progress.");
    }
    else // If no vote is in progress, and it is past the cooldown time, start the vote.
    {
        gLastVoteTime = GetTime();
        StartVote();
    }
    return Plugin_Handled;
}

// DFGM command handler
Action:OnDFGMCommand(int client, int args)
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
void StartVote()
{
    new Menu:menu = CreateMenu(HandleVoteMenu);
    if (gFGMEnabled)
    {
        SetMenuTitle(menu, "Keep Few Good Men enabled?");
    }
    else
    {
        SetMenuTitle(menu, "Enable Few Good Men?");
    }
    AddMenuItem(menu, "yes", "Yes");
    AddMenuItem(menu, "no", "No");
    SetMenuExitButton(menu, false);
    SetVoteResultCallback(menu, VoteResult);
    VoteMenuToAll(menu, 15);
}

// Done to make sure ties result in status quo, and not random chance.
void VoteResult(Menu:menu, int num_votes, int num_clients, const int[][] client_info, int num_items, const int[][] item_info)
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
            DisableFGM();
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

void EnableFGM()
{
    gFGMEnabled = true;
    winningTeam = UNDEFINED;
    lastWinner = UNDEFINED;
    gConsecutiveWins = 0;
    // Start paying attention to round wins
    HookEvent("teamplay_round_win", OnRoundWin);
    HookEvent("teamplay_round_start", OnRoundStart);
    AddCommandListener(OnTeamChange, "jointeam");
    // HookEvent("player_team", OnTeamChange);
    // Disable autobalance so we don't have problems
    ServerCommand("mp_autoteambalance 0");
    ServerCommand("mp_teams_unbalance_limit 0");
}

void DisableFGM()
{
    gFGMEnabled = false;
    // Stop paying attention to round wins
    UnhookEvent("teamplay_round_win", OnRoundWin);
    UnhookEvent("teamplay_round_start", OnRoundStart);
    RemoveCommandListener(OnTeamChange, "jointeam");
    // Re-enable autobalance
    ServerCommand("mp_autoteambalance 1");
    ServerCommand("mp_teams_unbalance_limit 1");
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
Action:OnRoundWin(Event:event, const char[] name, bool dontBroadcast)
{
    int winner = event.GetInt("team");
    // Make sure either team won
    if (winner == BLU_TEAM || winner == RED_TEAM)
    {
        HandleWinningTeam(winner);
    }
    // Update scoreHistory
    for(int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i))
        {
            // Update score delta
            scoreHistory[i].scoreQueue[scoreHistory[i].queuePointer] = GetPlayerResourceTotalScore(i) - scoreHistory[i].currentScore;
            // Update currentScore
            scoreHistory[i].currentScore = GetPlayerResourceTotalScore(i);
            // Update score delta sum
            scoreHistory[i].scoreTotalDelta += scoreHistory[i].scoreQueue[scoreHistory[i].queuePointer];
            // Set queue pointer
            scoreHistory[i].queuePointer = (scoreHistory[i].queuePointer + 1) % 3;
            // If queue pointer is 0, that means queue looped back, so set useCurrentScore to false
            if (scoreHistory[i].queuePointer == 0)
            {
                scoreHistory[i].useCurrentScore = false;
            }
        }
    }

    return Plugin_Handled;
}

void HandleWinningTeam(int latestWinner)
{
    if (winningTeam != UNDEFINED)
    {
        // There is a consecutive winner
        if (latestWinner == winningTeam)
        {
            // The consecutive winner won again
            gConsecutiveWins += 1;
        }
        else
        {
            // The consecutive winner lost
            if (gConsecutiveWins == 0)
            {
                // The consecutive winner lost twice in a row
                winningTeam = latestWinner;
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
        if (gConsecutiveWins == 0 || lastWinner != latestWinner)
        {
            // It's the first time latestWinner wins, or it's the first round
            gConsecutiveWins = 1;
            lastWinner = latestWinner;
            return;
        }
        else // if ((gConsecutiveWins != 0) && (lastWinner == latestWinner))
        {
            // It's the second time in a row latestWinner wins
            gConsecutiveWins = 2;
            winningTeam = latestWinner;
        }
    }

    // Evaluate gConsecutiveWins
    if (gConsecutiveWins > 1)
    {
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
}


// Round start event handler
Action:OnRoundStart(Event:event, const char[] name, bool dontBroadcast)
{
    // Evaluate gConsecutiveWins. Don't do anything if no consecutive wins. Don't do anything if winningTeam only has one player.
    if ((gConsecutiveWins > 1) && GetTeamClientCount(winningTeam) > 1)
    {
        // Get the least contributing team member of the losing team
        int worstContributor = GetLowestScoreOnWinningTeam();
        ChangeClientTeam(worstContributor, 5 - winningTeam);
        PrintToChatAll("[FewGoodMen] Moving a player to the losing team.");
    }
    
    return Plugin_Handled;
}



int GetLowestScoreOnWinningTeam()
{
    int lowestScore = 2048; // Arbitrarily large 
    int index = 0;
    // Get minimum score on winning team
    for(int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && (GetClientTeam(i) == winningTeam))
        {
            if (scoreHistory[i].useCurrentScore != true)
            {
                if (scoreHistory[i].scoreTotalDelta < lowestScore)
                {
                    lowestScore = scoreHistory[i].scoreTotalDelta;
                    index = i;
                }
            }
            else if (scoreHistory[i].currentScore < lowestScore)
            {
                lowestScore = scoreHistory[i].currentScore;
                index = i;
            }
        }
    }

    return index;
}

// Get score of client from clientID
int GetPlayerResourceTotalScore(int client)
{
    int playerSourceEnt = GetPlayerResourceEntity();
    return GetEntProp(playerSourceEnt, Prop_Send, "m_iTotalScore", _, client);
}


Action:OnTeamChange(int client, const char[] command, int argc)
{
    char argument[5];
    GetCmdArg(1, argument, sizeof(argument));
    if (strcmp(argument, "red", false) == 0 && winningTeam == RED_TEAM)
    {
        PrintToChat(client, "[FewGoodMen] You may not join the winning team.");
        return Plugin_Handled;
    }
    else if (strcmp(argument, "blue", false) == 0 && winningTeam == BLU_TEAM)
    {
        PrintToChat(client, "[FewGoodMen] You may not join the winning team.");
        return Plugin_Handled;
    }
    else if (strcmp(argument, "auto", false) == 0 && winningTeam > 1)
    {
        // Change client to losing team
        ChangeClientTeam(client, 5 - winningTeam);
        return Plugin_Handled;
    }

    return Plugin_Continue;
}