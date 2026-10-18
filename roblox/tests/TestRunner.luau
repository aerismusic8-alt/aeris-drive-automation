--!strict
-- Minimal zero-dependency test framework for the standalone Luau CLI.
--
-- Usage from a test file:
--   local t = require("./TestRunner")
--   t.test("name", function() t.assertEqual(1, 1) end)
--   t.finish()

local TestRunner = {}

local passed = 0
local failed = 0
local failures: { string } = {}
local currentSuite = "default"

function TestRunner.suite(name: string)
	currentSuite = name
end

function TestRunner.test(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if ok then
		passed += 1
		print(string.format("  PASS  [%s] %s", currentSuite, name))
	else
		failed += 1
		local message = string.format("[%s] %s -> %s", currentSuite, name, tostring(err))
		table.insert(failures, message)
		print(string.format("  FAIL  %s", message))
	end
end

local function fail(message: string): never
	error(message, 3)
end

function TestRunner.assertEqual(actual: any, expected: any, label: string?)
	if actual ~= expected then
		fail(string.format(
			"%sexpected %s but got %s",
			label and (label .. ": ") or "",
			tostring(expected),
			tostring(actual)
		))
	end
end

function TestRunner.assertNotEqual(actual: any, unexpected: any, label: string?)
	if actual == unexpected then
		fail(string.format("%sdid not expect %s", label and (label .. ": ") or "", tostring(unexpected)))
	end
end

function TestRunner.assertTrue(value: any, label: string?)
	if not value then
		fail(string.format("%sexpected truthy, got %s", label and (label .. ": ") or "", tostring(value)))
	end
end

function TestRunner.assertFalse(value: any, label: string?)
	if value then
		fail(string.format("%sexpected falsy, got %s", label and (label .. ": ") or "", tostring(value)))
	end
end

function TestRunner.assertNil(value: any, label: string?)
	if value ~= nil then
		fail(string.format("%sexpected nil, got %s", label and (label .. ": ") or "", tostring(value)))
	end
end

function TestRunner.assertNotNil(value: any, label: string?)
	if value == nil then
		fail(string.format("%sexpected non-nil", label and (label .. ": ") or ""))
	end
end

function TestRunner.assertNear(actual: number, expected: number, epsilon: number?, label: string?)
	local eps = epsilon or 1e-9
	if math.abs(actual - expected) > eps then
		fail(string.format(
			"%sexpected %s +/- %s but got %s",
			label and (label .. ": ") or "",
			tostring(expected),
			tostring(eps),
			tostring(actual)
		))
	end
end

function TestRunner.assertGreater(actual: number, bound: number, label: string?)
	if not (actual > bound) then
		fail(string.format(
			"%sexpected > %s but got %s",
			label and (label .. ": ") or "",
			tostring(bound),
			tostring(actual)
		))
	end
end

function TestRunner.assertLess(actual: number, bound: number, label: string?)
	if not (actual < bound) then
		fail(string.format(
			"%sexpected < %s but got %s",
			label and (label .. ": ") or "",
			tostring(bound),
			tostring(actual)
		))
	end
end

function TestRunner.assertContains(haystack: string, needle: string, label: string?)
	if not string.find(haystack, needle, 1, true) then
		fail(string.format(
			"%sexpected %q to contain %q",
			label and (label .. ": ") or "",
			haystack,
			needle
		))
	end
end

function TestRunner.assertThrows(fn: () -> (), label: string?)
	local ok = pcall(fn)
	if ok then
		fail(string.format("%sexpected an error", label and (label .. ": ") or ""))
	end
end

function TestRunner.finish(): number
	print("")
	print(string.format("TOTAL: %d passed, %d failed", passed, failed))
	if failed > 0 then
		print("FAILURES:")
		for _, message in ipairs(failures) do
			print("  - " .. message)
		end
	end
	return failed
end

function TestRunner.stats(): (number, number)
	return passed, failed
end

return TestRunner
