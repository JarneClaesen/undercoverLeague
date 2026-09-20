package game

import (
	"slices"
	"testing"
)

func has(l *Lobby, player, id string) bool { return slices.Contains(l.Achievements[player], id) }

func TestScoresCivilianWin(t *testing.T) {
	// A, B, C civilians, D undercover (wordless). Round 1 removes C (A and
	// B on C, D skips); round 2 unanimously removes D, who guesses wrong.
	l := newStarted(t, "A", "B", "C", "D")
	toPlaying(t, l)
	pin(l, []string{"A", "B", "C", "D"}, map[string]string{"D": RoleUndercover})
	castAll(t, l, map[string]string{"A": "C", "B": "C", "C": "A"})
	castAll(t, l, map[string]string{"A": "D", "B": "D"})
	if l.GamePhase != PhaseLastGuess {
		t.Fatalf("phase %s", l.GamePhase)
	}
	l.Guess("D", "wrong", t0, testRNG())
	if l.GamePhase != PhaseGameOver || l.Winner != WinnerCivilians {
		t.Fatalf("phase %s winner %s", l.GamePhase, l.Winner)
	}
	// Every civilian +1, the two who voted D in the deciding ballot +1 more.
	if l.Scores["A"] != 2 || l.Scores["B"] != 2 || l.Scores["C"] != 1 || l.Scores["D"] != 0 {
		t.Errorf("scores %v", l.Scores)
	}
	if _, ok := l.Scores["D"]; !ok {
		t.Error("impostor has no scoreboard row")
	}
	if l.GamesPlayed != 1 {
		t.Errorf("games played %d", l.GamesPlayed)
	}
	want := map[string]PlayerStats{
		"A": {CivilianSurvivals: 1, Games: 1}, "B": {CivilianSurvivals: 1, Games: 1},
		"C": {Games: 1}, "D": {ImpostorGames: 1, Games: 1},
	}
	for p, st := range want {
		if l.Stats[p] != st {
			t.Errorf("%s stats %+v, want %+v", p, l.Stats[p], st)
		}
	}
	// C: first_blood. D: public_enemy (unanimous). A and B: sharp_eye needs
	// every vote on an impostor (their first hit C, so no), but they were
	// the unanimous ballot that removed an impostor.
	if !has(l, "C", AchFirstBlood) || has(l, "D", AchFirstBlood) {
		t.Errorf("first blood: %v", l.Achievements)
	}
	if !has(l, "D", AchPublicEnemy) || has(l, "C", AchPublicEnemy) {
		t.Errorf("public enemy: %v", l.Achievements)
	}
	if has(l, "A", AchSharpEye) || has(l, "B", AchSharpEye) {
		t.Errorf("sharp eye: %v", l.Achievements)
	}
	if !has(l, "A", AchUnanimousJustice) || !has(l, "B", AchUnanimousJustice) || has(l, "D", AchUnanimousJustice) {
		t.Errorf("unanimous justice: %v", l.Achievements)
	}
	if has(l, "D", AchMindReader) || has(l, "D", AchSurvivor) {
		t.Errorf("impostor achievements on a loss: %v", l.Achievements)
	}
	for _, list := range l.Achievements {
		if !slices.IsSorted(list) {
			t.Errorf("unsorted %v", list)
		}
	}
}

func TestSharpEye(t *testing.T) {
	s := DefaultSettings()
	s.Undercovers = 2
	s.DecoyWord = true
	l := startWith(t, s, "A", "B", "C", "D", "E", "F")
	toPlaying(t, l)
	pin(l, []string{"A", "B", "C", "D", "E", "F"}, map[string]string{"D": RoleUndercover, "E": RoleUndercover})
	// A and F hit D then E; B hits D then skips; C hits D then misses.
	castAll(t, l, map[string]string{"A": "D", "B": "D", "C": "D", "F": "D", "D": "A", "E": "A"})
	castAll(t, l, map[string]string{"A": "E", "B": SkipVote, "C": "A", "F": "E", "E": "C"})
	if l.Winner != WinnerCivilians {
		t.Fatalf("winner %s", l.Winner)
	}
	if !has(l, "A", AchSharpEye) || !has(l, "F", AchSharpEye) || has(l, "B", AchSharpEye) || has(l, "C", AchSharpEye) {
		t.Errorf("sharp eye: %v", l.Achievements)
	}
}

func TestScoresOutnumbered(t *testing.T) {
	s := DefaultSettings()
	s.Undercovers = 2
	s.DecoyWord = true
	l := startWith(t, s, "A", "B", "C", "D", "E")
	toPlaying(t, l)
	pin(l, []string{"A", "B", "C", "D", "E"}, map[string]string{"D": RoleUndercover, "E": RoleUndercover})
	castAll(t, l, map[string]string{"A": "E", "B": "E", "C": "E", "D": "E"}) // E out (decoy: no guess)
	castAll(t, l, map[string]string{"B": "A", "C": "A", "D": "A"})           // A out: 1 v 2
	if l.GamePhase != PhasePlaying {
		t.Fatalf("phase %s at one impostor against two", l.GamePhase)
	}
	castAll(t, l, map[string]string{"C": "B", "D": "B"}) // B out: 1 v 1
	if l.GamePhase != PhaseGameOver || l.Winner != WinnerUndercover || l.WinReason != WinOutnumbered {
		t.Fatalf("phase %s winner %s reason %s", l.GamePhase, l.Winner, l.WinReason)
	}
	if l.Scores["D"] != 3 || l.Scores["E"] != 1 || l.Scores["A"] != 0 || l.Scores["B"] != 0 {
		t.Errorf("scores %v", l.Scores)
	}
	if !has(l, "D", AchSurvivor) || has(l, "E", AchSurvivor) {
		t.Errorf("survivor: %v", l.Achievements)
	}
	if !has(l, "D", AchDoubleAgent) || has(l, "E", AchDoubleAgent) {
		t.Errorf("double agent: %v", l.Achievements)
	}
	if !has(l, "E", AchPublicEnemy) || !has(l, "E", AchFirstBlood) {
		t.Errorf("E: %v", l.Achievements["E"])
	}
	if has(l, "A", AchIronWall) || l.Stats["A"].CivilianSurvivals != 0 || l.Stats["D"].ImpostorGames != 1 {
		t.Errorf("stats %v", l.Stats)
	}
}

func TestScoresCorrectGuess(t *testing.T) {
	s := DefaultSettings()
	s.DecoyWord = true
	s.MrWhites = 1
	l := startWith(t, s, "A", "B", "C", "D", "E")
	toPlaying(t, l)
	pin(l, []string{"A", "B", "C", "D", "E"}, map[string]string{"D": RoleUndercover, "E": RoleMrWhite})
	castAll(t, l, map[string]string{"A": "E", "B": "E", "C": "E"})
	l.Guess("E", l.SelectedWord, t0, testRNG())
	if l.Winner != WinnerMrWhite {
		t.Fatalf("winner %s", l.Winner)
	}
	// Only the guesser scores; the other impostor gets nothing.
	if l.Scores["E"] != 3 || l.Scores["D"] != 0 || l.Scores["A"] != 0 {
		t.Errorf("scores %v", l.Scores)
	}
	if !has(l, "E", AchMindReader) || has(l, "D", AchSurvivor) || has(l, "D", AchMindReader) {
		t.Errorf("achievements %v", l.Achievements)
	}
}

func TestSilentHand(t *testing.T) {
	s := DefaultSettings()
	s.ClueLog = true
	s.DecoyWord = true
	l := startWith(t, s, "A", "B", "C", "D")
	toPlaying(t, l)
	pin(l, []string{"A", "B", "C", "D"}, map[string]string{"D": RoleUndercover})
	castAll(t, l, map[string]string{"A": "C", "B": "C", "D": "C"}) // nobody ever votes D
	castAll(t, l, map[string]string{"A": "B", "D": "B"})
	if l.Winner != WinnerUndercover {
		t.Fatalf("winner %s", l.Winner)
	}
	if !has(l, "D", AchSilentHand) {
		t.Errorf("silent hand: %v", l.Achievements)
	}
	// Without the clue log the same game earns nothing of the sort.
	s.ClueLog = false
	l = startWith(t, s, "A", "B", "C", "D")
	toPlaying(t, l)
	pin(l, []string{"A", "B", "C", "D"}, map[string]string{"D": RoleUndercover})
	castAll(t, l, map[string]string{"A": "C", "B": "C", "D": "C"})
	castAll(t, l, map[string]string{"A": "B", "D": "B"})
	if has(l, "D", AchSilentHand) {
		t.Errorf("silent hand without the log: %v", l.Achievements)
	}
}

func TestIronWallAndVeteran(t *testing.T) {
	l := newStarted(t, "A", "B", "C", "D")
	toPlaying(t, l)
	pin(l, []string{"A", "B", "C", "D"}, map[string]string{"D": RoleUndercover})
	l.Stats["A"] = PlayerStats{CivilianSurvivals: 2, Games: 9}
	l.Stats["B"] = PlayerStats{CivilianSurvivals: 2, Games: 2}
	castAll(t, l, map[string]string{"A": "D", "B": "D", "C": "D"})
	l.Guess("D", "nope", t0, testRNG())
	if l.Winner != WinnerCivilians {
		t.Fatalf("winner %s", l.Winner)
	}
	if !has(l, "A", AchIronWall) || !has(l, "B", AchIronWall) || has(l, "C", AchIronWall) {
		t.Errorf("iron wall: %v", l.Achievements)
	}
	if !has(l, "A", AchVeteran) || has(l, "B", AchVeteran) {
		t.Errorf("veteran: %v", l.Achievements)
	}
	if l.Stats["A"] != (PlayerStats{CivilianSurvivals: 3, Games: 10}) {
		t.Errorf("stats A %+v", l.Stats["A"])
	}
}

func TestAwardOnceAndPersist(t *testing.T) {
	l := newStarted(t, "A", "B", "C", "D")
	toPlaying(t, l)
	pin(l, []string{"A", "B", "C", "D"}, map[string]string{"D": RoleUndercover})
	castAll(t, l, map[string]string{"A": "D", "B": "D", "C": "D"})
	l.Guess("D", "nope", t0, testRNG())
	scores := map[string]int{"A": 2, "B": 2, "C": 2, "D": 0}
	for p, n := range scores {
		if l.Scores[p] != n {
			t.Fatalf("scores %v", l.Scores)
		}
	}
	// Repeated advances and a leave after game over award nothing twice.
	l.Advance(t0, testRNG())
	l.Advance(t0, testRNG())
	l.Leave("B", t0, testRNG())
	for p, n := range scores {
		if l.Scores[p] != n {
			t.Errorf("scores changed: %v", l.Scores)
		}
	}
	if l.GamesPlayed != 1 {
		t.Errorf("games played %d", l.GamesPlayed)
	}
	// The leaver's row survives; the records survive play again, reset
	// and a new game, and the view carries them.
	l.PlayAgain("A")
	if l.Scores["B"] != 2 || l.Stats["B"].Games != 1 || !has(l, "B", AchUnanimousJustice) {
		t.Errorf("records lost: %v %v %v", l.Scores, l.Stats, l.Achievements)
	}
	l.Join("E")
	l.Start("A", testRNG(), testCatalog())
	l.Reset("A")
	if l.Scores["A"] != 2 || l.GamesPlayed != 1 {
		t.Errorf("records lost across games: %v", l.Scores)
	}
	v := l.ViewFor("E", nil, nil, t0)
	if v.Scores["A"] != 2 || v.GamesPlayed != 1 || v.Stats["A"].Games != 1 || len(v.Achievements["A"]) == 0 {
		t.Errorf("view records %v %v", v.Scores, v.Achievements)
	}
	// The view's copies are detached from the lobby.
	v.Scores["A"] = 99
	v.Achievements["A"][0] = "x"
	if l.Scores["A"] == 99 || l.Achievements["A"][0] == "x" {
		t.Error("view aliases lobby records")
	}
}

// A civilian win by the undercover leaving has no deciding ballot; nobody
// gets the vote bonus but the civilians still score.
func TestScoresWithoutBallot(t *testing.T) {
	l := newStarted(t, "A", "B", "C", "D")
	toPlaying(t, l)
	pin(l, []string{"A", "B", "C", "D"}, map[string]string{"D": RoleUndercover})
	l.Leave("D", t0, testRNG())
	if l.GamePhase != PhaseGameOver || l.Winner != WinnerCivilians {
		t.Fatalf("phase %s", l.GamePhase)
	}
	if l.Scores["A"] != 1 || l.Scores["B"] != 1 || l.Scores["C"] != 1 || len(l.Ballots) != 0 {
		t.Errorf("scores %v ballots %v", l.Scores, l.Ballots)
	}
	if len(l.Achievements) != 0 {
		t.Errorf("achievements without a ballot: %v", l.Achievements)
	}
}
