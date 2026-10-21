local Rules = {}
Rules.MinimumPlayers = 2
Rules.WarmupSeconds = 7
Rules.BuySeconds = 10
Rules.RoundSeconds = 75
Rules.BombSeconds = 30
Rules.EndSeconds = 5
Rules.ScoreToWin = 4

function Rules.winner(phase, bombStatus, attackers, defenders, remaining)
    if phase == "Planted" then
        if bombStatus == "Defused" then return "Defenders", "Bomb Defused" end
        if remaining <= 0 then return "Attackers", "Bomb Detonated" end
        if defenders == 0 then return "Attackers", "Team Eliminated" end
        return nil
    end
    if phase ~= "Combat" then return nil end
    if defenders == 0 then return "Attackers", "Team Eliminated" end
    if attackers == 0 then return "Defenders", "Team Eliminated" end
    if remaining <= 0 then return "Defenders", "Time Expired" end
    return nil
end
return Rules