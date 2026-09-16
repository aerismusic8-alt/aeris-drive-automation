export function verifyJobResult(job, evidence) {
  const reasons=[];
  if (!job?.result) reasons.push('missing_result');
  if (!evidence?.result) reasons.push('missing_evidence_result');
  if (evidence?.result && job?.result !== evidence.result) reasons.push('result_mismatch');
  if (evidence?.verification?.verified !== true) reasons.push('verification_not_passed');
  return {verified: reasons.length===0,reasons};
}
