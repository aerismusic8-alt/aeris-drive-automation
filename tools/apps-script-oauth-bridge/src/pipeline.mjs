import crypto from "node:crypto";
import fs from "node:fs/promises";
import path from "node:path";

export function verifyPreflight(content) {
  if (!content || !Array.isArray(content.files) || content.files.length === 0) {
    throw new Error("COMPLETE_PROJECT_CONTENT_REQUIRED");
  }
  const manifest = content.files.find((file) => file.name === "appsscript" && file.type === "JSON");
  if (!manifest) throw new Error("APPSCRIPT_MANIFEST_REQUIRED");
  return true;
}

export function applyPatch(content, transform) {
  verifyPreflight(content);
  if (typeof transform !== "function") throw new Error("PATCH_FUNCTION_REQUIRED");
  const next = transform(structuredClone(content));
  verifyPreflight(next);
  return next;
}

export async function backup(content, directory) {
  verifyPreflight(content);
  await fs.mkdir(directory, { recursive: true, mode: 0o700 });
  const stamp = new Date().toISOString().replace(/[:.]/g, "-");
  const digest = crypto.createHash("sha256").update(JSON.stringify(content)).digest("hex");
  const file = path.join(directory, `apps-script-backup-${stamp}-${digest.slice(0, 12)}.json`);
  await fs.writeFile(file, JSON.stringify(content, null, 2), { encoding: "utf8", mode: 0o600, flag: "wx" });
  return { file, sha256: digest };
}
