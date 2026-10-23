local Rules = {}
Rules.MinimumPlayers = 2
Rules.WarmupSeconds = 7
Rules.BuySeconds = 10
Rules.RoundSeconds = 75
Rules.BombSeconds = 30
Rules.EndSeconds = 5
Rules.ScoreToWin = 4

---How many players a round needs right now.
---
---A lone player must still be able to play. The game shipped gating every round
---on two players, so the first player to arrive -- and the only player, on a
---new experience with no one else on the server -- was parked on "Waiting for
---Players" forever. The page loaded, the menu came up, PLAY worked, and then
---nothing ever happened: that is the "looks unplayable" report, and this is its
---cause.
---
---One player is a practice round: the loop runs exactly as it does with two, so
---warm-up, buy, combat and the bomb all work and can be learned solo. The
---competitive gate is unchanged -- from two players up the rules are what they
---were, so nobody can win a scored round by being alone.
function Rules.requiredPlayers(count)
        if count <= 1 then return 1 end
        return Rules.MinimumPlayers
end

---Who won, if anyone, given the phase the round is in.
---
---`practice` is the one-player round. It suppresses the elimination wins and
---keeps the objective ones: a lone player has no enemy to eliminate, so
---"defenders are all dead" would end combat the instant it began and the round
---could never be played. The bomb and the clock still decide the round, so the
---practice round has the same goal as a real one -- plant, or hold the site --
---rather than a rule invented for it.
function Rules.winner(phase, bombStatus, attackers, defenders, remaining, practice)
    if phase == "Planted" then
        if bombStatus == "Defused" then return "Defenders", "Bomb Defused" end
        if remaining <= 0 then return "Attackers", "Bomb Detonated" end
        if defenders == 0 and not practice then return "Attackers", "Team Eliminated" end
        return nil
    end
    if phase ~= "Combat" then return nil end
    if defenders == 0 and not practice then return "Attackers", "Team Eliminated" end
    if attackers == 0 and not practice then return "Defenders", "Team Eliminated" end
    if remaining <= 0 then return "Defenders", "Time Expired" end
    return nil
end
return Rules