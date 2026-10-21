 a heavy one-handed melee/mining tool. Pickaxe2Capability creates an equippable Tool with a single heavy swing via the MeleeTool Architect.',
				capability_selection = "Pickaxe2Capability",
				overall_size_reasoning = "A pickaxe for a Roblox avatar should be roughly 0.6m wide (head), 1.0m tall (handle), and 0.15m deep.",
				overall_size_selection = { x = 0.6, y = 1.0, z = 0.15 },
			},
		},
	}
end

function Pickaxe2:getConfigureCapabilityExamples()
	return {}
end

function Pickaxe2:bind(generatedModels: { [string]: Model }, parameters: { [string]: any }): Tool
	local isValid, errorMsg = self:validateConfig(parameters)
	if not isValid then
		error("Pickaxe2Capability configuration error: " .. errorMsg)
	end

	local pickaxeModel = generatedModels["pickaxe"]
	if not pickaxeModel then
		error("Pickaxe2Capability: Could not find 'pickaxe' model")
	end

	return MakeFunctional(pickaxeModel)
end

return Pickaxe2
