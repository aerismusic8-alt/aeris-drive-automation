 a hand-thrown explosive that detonates after a short fuse. Grenade3Capability creates an equippable Tool that launches a timed explosive via the Throwable Behavior.',
				capability_selection = "Grenade3Capability",
				overall_size_reasoning = "A frag grenade for a Roblox avatar should be roughly 0.06m wide, 0.10m tall, and 0.06m deep.",
				overall_size_selection = { x = 0.06, y = 0.10, z = 0.06 },
			},
		},
	}
end

function Grenade3:getConfigureCapabilityExamples()
	return {}
end

function Grenade3:bind(generatedModels: { [string]: Model }, parameters: { [string]: any }): Tool
	local isValid, errorMsg = self:validateConfig(parameters)
	if not isValid then
		error("Grenade3Capability configuration error: " .. errorMsg)
	end

	local grenadeModel = generatedModels["grenade"]
	if not grenadeModel then
		error("Grenade3Capability: Could not find 'grenade' model")
	end

	return MakeFunctional(grenadeModel)
end

return Grenade3
