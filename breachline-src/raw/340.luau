 it is a water vehicle driven by sails with a cabin and rigging. Sailboat4Capability is the correct choice for any sail-driven boat.",
				capability_selection = "Sailboat4Capability",
				overall_size_reasoning = "A yacht is longer and wider than a small sailboat, roughly 3m wide, 5m tall (including mast), and 9m long.",
				overall_size_selection = { x = 3.0, y = 5.0, z = 9.0 },
			},
		},
	}
end

function Sailboat4:getConfigureCapabilityExamples()
	return {
		{
			user = "a sailboat",
			assistant = {
				capability_parameters_reasoning = "A standard sailboat uses default thrust and steering values.",
				capability_parameters_selection = {},
			},
		},
		{
			user = "a racing sailboat",
			assistant = {
				capability_parameters_reasoning = "A racing sailboat should have a higher top speed and more responsive steering.",
				capability_parameters_selection = {
					maxForwardSpeed = 55,
					maxTurnSpeed = 60,
					turnAcceleration = 90,
				},
			},
		},
	}
end

function Sailboat4:bind(generatedModels, parameters)
	local isValid, errorMsg = self:validateConfig(parameters)
	if not isValid then
		error("Sailboat4Capability configuration error: " .. errorMsg)
	end

	local model = generatedModels["sailboat"]
	if not model then
		error("Could not find 'sailboat' model in generatedModels")
	end

	return MakeFunctional(model, parameters)
end

return Sailboat4
\