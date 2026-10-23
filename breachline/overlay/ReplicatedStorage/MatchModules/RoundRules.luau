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

---The money a player is given when they have no history.
Rules.StartMoney = 800

---The most money a player may hold.
---
---Without a ceiling the loss bonus compounds across a long match, both teams
---stop having to choose at the shop, and the economy stops being a decision.
Rules.MaxMoney = 16000

---The flat win bonus.
Rules.WinReward = 1500

---The loss bonus before any streak, and what each consecutive loss adds.
---
---This is the loss bonus that keeps a match close. With a flat payout a team
---that loses the first few rounds is priced out of the rest of the match: the
---winners can afford armor and the SMG every round while the losers cannot, so
---the opening rounds decide the match and the rest is a formality. Paying more
---after each loss lets the losing team buy again and keeps the score live.
Rules.LossReward = 900
Rules.LossStreakStep = 500

---The streak at which the loss bonus stops growing. Past this a long match is
---not decided by who lost first.
Rules.LossStreakCap = 5

---What a finished round pays one player.
---
---`won` is whether this player's team took the round. `lossStreak` is how many
---rounds that team has now lost in a row, counting this one, so the first loss
---passes 1. A win pays the flat bonus; a loss pays the base plus a step per
---consecutive loss, held at the cap.
function Rules.roundReward(won, lossStreak)
    if won then return Rules.WinReward end
    local streak = math.clamp(lossStreak or 1, 1, Rules.LossStreakCap)
    return Rules.LossReward + Rules.LossStreakStep * (streak - 1)
end

---Money after a payout, held at the ceiling.
---
---Kept here rather than at the call site so the ceiling has exactly one
---definition, and a payout cannot be written that quietly exceeds it.
function Rules.addMoney(money, amount)
    local held = if typeof(money) == "number" then money else 0
    return math.min(held + amount, Rules.MaxMoney)
end
return Rules