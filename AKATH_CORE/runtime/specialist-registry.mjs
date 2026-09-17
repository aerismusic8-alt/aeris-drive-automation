const SPECIALISTS = Object.freeze({
  execution: Object.freeze({
    id: 'PC1_MAIN_SPECIALIST',
    capability: 'execution',
    description: 'Default deterministic execution specialist for non-destructive AKATH work.'
  }),
  ai: Object.freeze({
    id: 'PC1_GEMINI_AI_SPECIALIST',
    capability: 'ai',
    description: 'Gemini-backed AI execution specialist for production AI tasks.'
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
