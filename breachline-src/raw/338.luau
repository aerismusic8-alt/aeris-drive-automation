 it is a water vehicle driven by a motor. MotorboatSimple2Capability is the correct choice for any motor-driven boat.',
				capability_selection = "MotorboatSimple2Capability",
				overall_size_reasoning = "A speedboat is sleek and low-profile, roughly 1.4m wide, 1.0m tall, and 5m long.",
				overall_size_selection = { x = 1.4, y = 1.0, z = 5.0 },
			},
		},
	}
end

function MotorboatSimple2:getConfigureCapabilityExamples()
	return {
		{
			user = "a motorboat",
			assistant = {
				capability_parameters_reasoning = "A standard motorboat uses default thrust and steering values. No overrides needed.",
				capability_parameters_selection = {},
			},
		},
		{
			user = "a fast motorboat",
			assistant = {
				capability_parameters_reasoning = "A fast motorboat should have a higher top speed.",
				capability_parameters_selection = {
					maxForwardSpeed = 60,
					maxReverseSpeed = 30,
				},
			},
		},
	}
end

function MotorboatSimple2:bind(generatedModels, parameters)
	local isValid, errorMsg = self:validateConfig(parameters)
	if not isValid then
		error("MotorboatSimple2Capability configuration error: " .. errorMsg)
	end

	local model = generatedModels["motorboat"]
	if not model then
		error("Could not find 'motorboat' model in generatedModels")
	end

	return MakeFunctional(model, parameters)
end

return MotorboatSimple2
