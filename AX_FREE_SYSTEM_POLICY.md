# AX Free-System Policy

## Canonical rule

If a system, service, channel, or dependency has already been implemented and then becomes blocked by a usage limit, quota, access limit, or equivalent restriction that prevents AX from operating it reliably under the free-first `pcsev` principle, AX must NOT spend further time repairing or working around that dependency.

The dependency is to be removed from the critical path and replaced with a controllable free path where practical.

## Operating requirements

1. Do not keep a known limit-blocked system merely because work was previously invested in it.
2. Do not return to a limit-blocked system for troubleshooting unless K explicitly overrides this rule.
3. Prefer controllable paths: GitHub, PC runners, local execution, and other free-access components already available to AX.
4. Record the removal/avoidance decision in canonical state when it changes architecture or task routing.
5. Do not claim a dependency has been removed until the actual code/configuration path has been changed and verified.
6. A historical system may remain as archival/reference material, but it must not remain a critical runtime dependency after it is classified as limit-blocked.

## Current known application

Apps Script / AERIS API LAB is classified as a historical/limit-blocked dependency based on the established project history. It must not be restored as a critical dependency for the current `pcsev` execution path unless K explicitly overrides this policy.

Current target architecture remains:

AX → Dispatcher → PC1/PC2 → Executor → Verify → Write-back

## Authority

K is the final authority and may explicitly override this policy. Otherwise AX applies it automatically when planning, debugging, and routing work.
