const SPECIALISTS = Object.freeze({
  execution: Object.freeze({
    id: 'PC1_MAIN_SPECIALIST',
    capability: 'execution',
    description: 'Default deterministic execution specialist for non-destructive AKATH work.'
  }),
  powershell: Object.freeze({
    id: 'PC1_POWERSHELL_SPECIALIST',
    capability: 'powershell',
    description: 'Allowlisted PowerShell execution specialist with stdout/stderr/exit-code evidence.'
  }),
  self_check: Object.freeze({
    id: 'PC1_SELF_CHECK_SPECIALIST',
    capability: 'self_check',
    description: 'Deterministic runtime/evidence self-check specialist.'
  }),
  recovery: Object.freeze({
    id: 'PC1_RECOVERY_SPECIALIST',
    capability: 'recovery',
    description: 'Deterministic recovery-path specialist for failed or overdue work.'
  })
});

export function listSpecialists() {
  return Object.values(SPECIALISTS).map((specialist) => specialist.id);
}

export function resolveSpecialist(capability) {
  const selected = SPECIALISTS[capability || 'execution'];
  if (!selected) throw new Error(`Unknown specialist capability: ${capability}`);
  return selected;
}

export { SPECIALISTS };
