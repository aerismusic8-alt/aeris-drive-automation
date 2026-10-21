 a short double-edged bladed melee weapon. Dagger3Capability creates an equippable Tool with fast swing and chain-swing attacks via the MeleeTool Architect.',
				capability_selection = "Dagger3Capability",
				overall_size_reasoning = "A dagger for a Roblox avatar should be roughly 0.03m wide, 0.35m long, and 0.02m deep (blade + hilt).",
				overall_size_selection = { x = 0.03, y = 0.35, z = 0.02 },
			},
		},
	}
end

function Dagger3:getConfigureCapabilityExamples()
	return {}
end

function Dagger3:bind(generatedModels: { [string]: Model }, parameters: { [string]: any }): Tool
	local isValid, errorMsg = self:validateConfig(parameters)
	if not isValid then
		error("Dagger3Capability configuration error: " .. errorMsg)
	end

	local daggerModel = generatedModels["dagger"]
	if not daggerModel then
		error("Dagger3Capability: Could not find 'dagger' model")
	end

	return MakeFunctional(daggerModel)
end

return Dagger3
