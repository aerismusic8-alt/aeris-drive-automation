 a one-handed bladed melee weapon. Sword4Capability creates an equippable Tool with swing and chain-swing attacks via the MeleeTool Architect.',
				capability_selection = "Sword4Capability",
				overall_size_reasoning = "A one-handed sword for a Roblox avatar should be roughly 0.1m wide, 0.15m deep, and 1.2m long (blade + handle).",
				overall_size_selection = { x = 0.1, y = 1.2, z = 0.15 },
			},
		},
	}
end

function Sword4:getConfigureCapabilityExamples()
	return {}
end

function Sword4:bind(generatedModels: { [string]: Model }, parameters: { [string]: any }): Tool
	local isValid, errorMsg = self:validateConfig(parameters)
	if not isValid then
		error("Sword4Capability configuration error: " .. errorMsg)
	end

	local swordModel = generatedModels["sword"]
	if not swordModel then
		error("Sword4Capability: Could not find 'sword' model")
	end

	return MakeFunctional(swordModel)
end

return Sword4
