-- Probe run inside Roblox Studio on PC1 via: --task RunScript
--
-- Answers one question: is Studio on PC1 signed in as a Roblox account, and
-- can that account see or create places? It never reads, copies or prints a
-- credential. It only asks Studio what it already knows about itself.

local lines = {}
local function add(k, v)
	table.insert(lines, tostring(k) .. "=" .. tostring(v))
end

add("PLACE_ID", game.PlaceId)
add("GAME_ID", game.GameId)
add("CREATOR_ID", game.CreatorId)
add("CREATOR_TYPE", tostring(game.CreatorType))

local ok, uid = pcall(function()
	return game:GetService("StudioService"):GetUserId()
end)
add("STUDIO_USER_ID", ok and uid or ("ERR:" .. tostring(uid)))

if ok and type(uid) == "number" and uid > 0 then
	local ok2, name = pcall(function()
		return game:GetService("Players"):GetNameFromUserIdAsync(uid)
	end)
	add("STUDIO_USER_NAME", ok2 and name or ("ERR:" .. tostring(name)))
	add("SIGNED_IN", true)
else
	add("STUDIO_USER_NAME", "n/a")
	add("SIGNED_IN", false)
end

-- Capability probe only: report whether the API exists, do not call it, so no
-- junk place is created on the account.
local ok3, hasCreate = pcall(function()
	local a = game:GetService("AssetService")
	return type(a.CreatePlaceAsync) == "function"
end)
add("ASSETSERVICE_CREATEPLACE", ok3 and hasCreate or ("ERR:" .. tostring(hasCreate)))

local ok4, hasPublish = pcall(function()
	local p = game:GetService("PublishService")
	return p ~= nil
end)
add("PUBLISHSERVICE_PRESENT", ok4 and hasPublish or ("ERR:" .. tostring(hasPublish)))

add("PROBE", "COMPLETE")
print(table.concat(lines, "\n"))
