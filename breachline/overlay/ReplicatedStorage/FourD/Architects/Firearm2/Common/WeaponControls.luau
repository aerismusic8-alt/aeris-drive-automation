--[[
	File: ReplicatedStorage/FourD/Architects/Firearm2/Common/WeaponControls.luau

	Which touch controls a weapon is allowed to show.

	Why this is its own module. The cluster draws a fixed set of buttons, and the
	only thing that varies between weapons is which of them mean anything. A weapon
	that aims down iron sights has no optic, so its SCOPE button does nothing and
	should not be on screen; a weapon whose AimMode is "scope" should show it. That
	decision is a pure function of the weapon's params, so it lives here where it
	can be tested without a phone, and the input module only has to call it.
]]--

local WeaponControls = {}

---Whether a weapon aims through a magnified optic rather than iron sights.
function WeaponControls.hasOptic(params): boolean
	if typeof(params) ~= "table" then return false end
	return params.AimMode == "scope"
end

---The cluster buttons that mean something for this weapon. A name mapped to
---false is hidden; a name that is absent is left as the cluster drew it. Only
---SCOPE is ever turned off -- the rest of the cluster is the same gun to gun.
function WeaponControls.available(params): { [string]: boolean }
	return {
		Scope = WeaponControls.hasOptic(params),
	}
end

return WeaponControls
