-- The run results shown when a squad comes back from a run, the old XP
-- bar, and the old deploy-pad panel (MainUI, Client.Modules.UIManager).
-- The old panel only shows if UIManager.Settings.NewPlayMenu is off.
return {
	Victory = "VICTORY",
	Defeat = "DEFEAT",
	RunOver = "RUN OVER",
	Reached = "Reached {Area}",
	Exp = "+{Amount} XP",
	Cash = "+${Amount}",
	Kills = "{Count} kills",
	-- The old XP bar.
	XpAmount = "{Into} / {Needed} XP",
	Level = "LEVEL {Level}",
	Cash2 = "${Amount}",
	-- The old deploy-pad panel.
	Old = {
		Deploying = "DEPLOYING...",
		SquadNames = "Squad: {Names}",
		SquadLine = "Squad ({Count}/{Size}, {Difficulty}): {Names}",
		DeployingIn = "DEPLOYING IN {Seconds}",
		StartNow = "START NOW",
		WaitingFor = "  -  waiting for {Count}",
		WaitingLeader = "WAITING FOR LEADER",
		JoinSquad = "{Name}'S SQUAD - JOIN",
		OpenSquad = "Open squad: {Count}/{Size} on {Difficulty}",
		Deploy = "DEPLOY",
		Solo = "Solo run on {Difficulty}",
		OpenButton = "OPEN SQUAD",
		SquadOf = "Squad of {Size} on {Difficulty}",
		CloseSquad = "Close squad",
		LeaveSquad = "Leave squad",
		ComingSoon = "Coming soon",
		NameJoin = ", ",
	},
}
