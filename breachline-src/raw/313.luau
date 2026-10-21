 a short one-handed bladed melee weapon. Knife2Capability creates an equippable Tool with swing and chain-swing attacks via the MeleeTool Architect.',
				capability_selection = "Knife2Capability",
				overall_size_reasoning = "A knife for a Roblox avatar should be roughly 0.04m wide, 0.3m long, and 0.02m deep (blade + handle).",
				overall_size_selection = { x = 0.04, y = 0.3, z = 0.02 },
			},
		},
	}
end

function Knife2:getConfigureCapabilityExamples()
	return {}
end

function Knife2:bind(generatedModels: { [string]: Model }, parameters: { [string]: any }): Tool
	local isValid, errorMsg = self:validateConfig(parameters)
	if not isValid then
		error("Knife2Capability configuration error: " .. errorMsg)
	end

	local knifeModel = generatedModels["knife"]
	if not knifeModel then
		error("Knife2Capability: Could not find 'knife' model")
	end

	return MakeFunctional(knifeModel)
end

return Knife2
