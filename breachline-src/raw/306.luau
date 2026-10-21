 a blunt one-handed melee weapon. Bat2Capability creates an equippable Tool with a single heavy swing via the MeleeTool Architect.',
				capability_selection = "Bat2Capability",
				overall_size_reasoning = "A baseball bat for a Roblox avatar should be roughly 0.08m wide, 1.0m long, and 0.08m deep (barrel + handle).",
				overall_size_selection = { x = 0.08, y = 1.0, z = 0.08 },
			},
		},
	}
end

function Bat2:getConfigureCapabilityExamples()
	return {}
end

function Bat2:bind(generatedModels: { [string]: Model }, parameters: { [string]: any }): Tool
	local isValid, errorMsg = self:validateConfig(parameters)
	if not isValid then
		error("Bat2Capability configuration error: " .. errorMsg)
	end

	local batModel = generatedModels["bat"]
	if not batModel then
		error("Bat2Capability: Could not find 'bat' model")
	end

	return MakeFunctional(batModel)
end

return Bat2
