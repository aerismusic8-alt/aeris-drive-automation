-- When using Deferred signal mode: scripts parented to the car are not able to listen to its .Destroying event when it is
-- destroyed. This script is cloned and used to listen to the .Destroying even in a separate thread.

local bindToCarEvent = script.BindToCar

bindToCarEvent.Event:Connect(function(car: Model, callback: () -> ())
	-- This should listen to .Destroying but falling off the world does not actually destroy the car, only parents it to nil.
	-- We'll listen to .AncestryChanged instead and check if the car has been parented to nil.
	car.AncestryChanged:Connect(function()
		if not car:IsDescendantOf(game) then
			callback()
			script:Destroy()
		end
	end)
end)
