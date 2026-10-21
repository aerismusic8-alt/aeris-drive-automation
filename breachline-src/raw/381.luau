-- Thin root-local server bootstrap for a completed edit-time FourD rig.
-- Runs on the server when Play starts. Always assigns a fresh instance id so
-- cloned templates do not share the attribute copied in Edit.

local HttpService = game:GetService("HttpService")

local root = script.Parent
root:SetAttribute("FourDRuntimeInstanceId", HttpService:GenerateGUID(false))
root:SetAttribute("FourDServerRuntimeVersion", 1)
-- Do NOT claim readiness here. FourDServerStatus is owned by the place-global
-- ServerScriptService.FourDServerRuntime, which sets it to "ready" only after
-- every declared server component has actually bound, or "failed" (with
-- FourDServerError) if one did not. Seeding "starting" means a place that is
-- missing that runtime reports un-ready rather than falsely ready -- the bug
-- this replaces was an unconditional "ready" that masked unbound handlers.
--
-- Seed it ONLY if nothing has set it yet. Server script execution order is
-- unspecified, so the FourDServerRuntime may have already finalized this rig to
-- "ready"/"failed" before this co-located bootstrap runs; an unconditional write
-- here would clobber that back to "starting" and the rig would look stuck.
if root:GetAttribute("FourDServerStatus") == nil then
	root:SetAttribute("FourDServerStatus", "starting")
	root:SetAttribute("FourDServerError", nil)
end

script:SetAttribute("RuntimeVersion", 1)
script:SetAttribute("RuntimeReady", true)
w