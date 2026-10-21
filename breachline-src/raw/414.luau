local bike = script.Parent.Parent.Parent
local redress = bike.Redress

local function updateRedress()
	local maxTorque = redress:GetAttribute("redressMaxTorque")
	local responsiveness = redress:GetAttribute("redressResponsiveness")

	redress.RedressOrientation.MaxTorque = maxTorque
	redress.RedressOrientation.Responsiveness = responsiveness
end

local function initialize()
	redress.AttributeChanged:Connect(updateRedress)
	updateRedress()
end

initialize()
a