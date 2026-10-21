-- Play a random sound from a list of sounds
local function playRandomPlayer(players: { AudioPlayer }, volume: number?)
	local playerTemplate = players[math.random(1, #players)]

	local player = playerTemplate:Clone()
	player.Volume *= (volume or 1)
	player.Parent = playerTemplate.Parent
	player:Play()

	-- Destroy the player once it has finished playing
	player.Ended:Once(function()
		player:Destroy()
	end)
end

return playRandomPlayer
