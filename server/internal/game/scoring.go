package game

import (
	"slices"
)

// Achievement ids. Titles and descriptions live on the client; the server
// only decides who earned what.
const (
	AchSurvivor         = "survivor"          // won as an impostor by outnumbering, still alive
	AchMindReader       = "mind_reader"       // correct last guess
	AchSharpEye         = "sharp_eye"         // civilian, >= 2 votes, every one hit an impostor
	AchPublicEnemy      = "public_enemy"      // eliminated by a unanimous ballot
	AchFirstBlood       = "first_blood"       // first player eliminated in a game
	AchIronWall         = "iron_wall"         // IronWallSurvivals civilian wins survived, in total
	AchDoubleAgent      = "double_agent"      // undercover with a decoy word, alive at game over
	AchSilentHand       = "silent_hand"       // clue log on, won as an impostor never voted for
	AchVeteran          = "veteran"           // VeteranGames games in this lobby
	AchUnanimousJustice = "unanimous_justice" // civilian in a unanimous ballot that removed an impostor
)

var AllAchievements = []string{
	AchSurvivor, AchMindReader, AchSharpEye, AchPublicEnemy, AchFirstBlood,
	AchIronWall, AchDoubleAgent, AchSilentHand, AchVeteran, AchUnanimousJustice,
}

const (
	IronWallSurvivals = 3
	VeteranGames      = 10

	scoreCivilianWin   = 1 // every civilian
	scoreVotedImpostor = 1 // extra, for voting an impostor in the deciding ballot
	scoreImpostorAlive = 3 // alive impostor at an outnumbering win
	scoreImpostorOut   = 1 // eliminated impostor at an outnumbering win
	scoreCorrectGuess  = 3 // the guesser
)

// award settles the game that just ended: scores, stats and achievements
// for everyone who had a seat in it. Called exactly once per game, by
// finish. Spectators get nothing; players who left keep whatever they
// earned.
func (l *Lobby) award() {
	l.GamesPlayed++
	alive := func(p string) bool { return slices.Contains(l.AlivePlayers, p) }
	civWin := l.Winner == WinnerCivilians
	var deciding map[string]string
	if n := len(l.Ballots); n > 0 {
		deciding = l.Ballots[n-1]
	}

	switch l.WinReason {
	case WinEliminated:
		for p, r := range l.Roles {
			if r == RoleCivilian {
				l.Scores[p] += scoreCivilianWin
			}
		}
		for voter, target := range deciding {
			if l.isImpostor(target) {
				l.Scores[voter] += scoreVotedImpostor
			}
		}
	case WinOutnumbered:
		for p := range l.Roles {
			if !l.isImpostor(p) {
				continue
			}
			if alive(p) {
				l.Scores[p] += scoreImpostorAlive
			} else {
				l.Scores[p] += scoreImpostorOut
			}
		}
	case WinGuess:
		if l.LastGuess != nil {
			l.Scores[l.LastGuess.Player] += scoreCorrectGuess
		}
	}

	for p, r := range l.Roles {
		if r == RoleSpectator {
			continue
		}
		l.Scores[p] += 0 // a row for everyone who played, even at zero
		st := l.Stats[p]
		st.Games++
		if l.isImpostor(p) {
			st.ImpostorGames++
		}
		if civWin && r == RoleCivilian && alive(p) {
			st.CivilianSurvivals++
		}
		l.Stats[p] = st
	}

	// Read the ballots back: who was ever voted for, how well each voter
	// aimed, the first elimination and the unanimous ones.
	votedFor := map[string]bool{}
	cast := map[string]int{}
	hits := map[string]int{}
	firstBlood := ""
	type elimination struct {
		target string
		voters []string
	}
	var unanimous []elimination
	for _, b := range l.Ballots {
		for voter, target := range b {
			cast[voter]++
			if target == SkipVote {
				continue
			}
			votedFor[target] = true
			if l.isImpostor(target) {
				hits[voter]++
			}
		}
		e := tallyBallot(b, nil)
		if e == "" {
			continue
		}
		if firstBlood == "" {
			firstBlood = e
		}
		if voters, ok := unanimousVoters(b, e); ok {
			unanimous = append(unanimous, elimination{e, voters})
		}
	}

	for p, r := range l.Roles {
		switch r {
		case RoleSpectator:
			continue
		case RoleCivilian:
			if cast[p] >= 2 && hits[p] == cast[p] {
				l.earn(p, AchSharpEye)
			}
			if civWin && alive(p) && l.Stats[p].CivilianSurvivals >= IronWallSurvivals {
				l.earn(p, AchIronWall)
			}
		default:
			if l.WinReason == WinOutnumbered && alive(p) {
				l.earn(p, AchSurvivor)
			}
			if r == RoleUndercover && l.DecoyWord != "" && alive(p) {
				l.earn(p, AchDoubleAgent)
			}
			if l.Settings.ClueLog && !civWin && !votedFor[p] {
				l.earn(p, AchSilentHand)
			}
		}
		if l.Stats[p].Games >= VeteranGames {
			l.earn(p, AchVeteran)
		}
	}
	if l.LastGuess != nil && l.LastGuess.Correct {
		l.earn(l.LastGuess.Player, AchMindReader)
	}
	if firstBlood != "" {
		l.earn(firstBlood, AchFirstBlood)
	}
	for _, e := range unanimous {
		l.earn(e.target, AchPublicEnemy)
		if !l.isImpostor(e.target) {
			continue
		}
		for _, v := range e.voters {
			if l.Roles[v] == RoleCivilian {
				l.earn(v, AchUnanimousJustice)
			}
		}
	}
}

// unanimousVoters reports whether every voter other than target chose
// target, and who they were.
func unanimousVoters(ballot map[string]string, target string) ([]string, bool) {
	var voters []string
	for voter, t := range ballot {
		if voter == target {
			continue
		}
		if t != target {
			return nil, false
		}
		voters = append(voters, voter)
	}
	return voters, len(voters) > 0
}

// earn records an achievement once, keeping the player's list sorted.
func (l *Lobby) earn(player, id string) {
	list := l.Achievements[player]
	if slices.Contains(list, id) {
		return
	}
	list = append(list, id)
	slices.Sort(list)
	l.Achievements[player] = list
}
