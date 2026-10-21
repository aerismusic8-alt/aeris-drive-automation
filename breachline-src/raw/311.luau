 a long curved one-handed bladed melee weapon. Katana3Capability creates an equippable Tool with swing and chain-swing attacks via the MeleeTool Architect.',
				capability_selection = "Katana3Capability",
				overall_size_reasoning = "A katana for a Roblox avatar should be roughly 0.05m wide, 1.1m long, and 0.05m deep (blade + handle).",
				overall_size_selection = { x = 0.05, y = 1.1, z = 0.05 },
			},
		},
	}
end

function Katana3:getConfigureCapabilityExamples()
	return {}
end

function Katana3:bind(generatedModels: { [string]: Model }, parameters: { [string]: any }): Tool
	local isValid, errorMsg = self:validateConfig(parameters)
	if not isValid then
		error("Katana3Capability configuration error: " .. errorMsg)
	end

	local katanaModel = generatedModels["katana"]
	if not katanaModel then
		error("Katana3Capability: Could not find 'katana' model")
	end

	return MakeFunctional(katanaModel)
end

return Katana3
i