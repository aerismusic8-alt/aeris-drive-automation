const AX_INPUT_RETRIEVAL_VERSION = "1.1.0";

function AX_RETRIEVE_DRIVE_INPUT(fileId) {
  const id = String(fileId || "").trim();
  if (!id) throw new Error("INPUT_FILE_ID_REQUIRED");
  const file = DriveApp.getFileById(id);
  const blob = file.getBlob();
  const bytes = blob.getBytes();
  const digest = Utilities.computeDigest(Utilities.DigestAlgorithm.SHA_256, bytes);
  const hash = digest.map(function(b) { const n = b < 0 ? b + 256 : b; return (n < 16 ? "0" : "") + n.toString(16); }).join("");
  return { status: "INPUT_RETRIEVED", retrieved: true, verified: true, fileId: id, fileName: file.getName(), mimeType: blob.getContentType(), sizeBytes: bytes.length, contentHash: hash, timestamp: new Date().toISOString() };
}

function AX_RETRIEVE_DRIVE_INPUT_BY_NAME(fileName) {
  const name = String(fileName || "").trim();
  if (!name) throw new Error("INPUT_FILE_NAME_REQUIRED");
  const files = DriveApp.getFilesByName(name);
  if (!files.hasNext()) return { status: "INPUT_NOT_FOUND", retrieved: false, verified: false };
  return AX_RETRIEVE_DRIVE_INPUT(files.next().getId());
}
