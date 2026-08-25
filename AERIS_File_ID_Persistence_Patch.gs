/* =========================================================
   AERIS FILE ID PERSISTENCE PATCH
   Run only after reviewing the main processCommandQueue() patch.

   PURPOSE
   -------
   Repair existing CREATE_FILE queue rows where the execution Result already
   contains a verified fileId but the Queue File ID column is blank.

   IMPORTANT
   ---------
   This helper does NOT replace processCommandQueue(). The permanent fix must
   also write result.fileId into the Queue File ID column immediately after a
   verified CREATE_FILE execution and before COMPLETED is persisted.
========================================================= */

function repairAERISFileIdPersistence() {
  const sheet = getQueueSheet();
  const data = sheet.getDataRange().getValues();
  if (data.length < 2) {
    return { status: "NO_QUEUE_ROWS", verified: true, repaired: 0 };
  }

  const headers = data[0].map(function(value) {
    return String(value).trim();
  });

  const commandIndex = headers.indexOf("Command");
  const fileIdIndex = headers.indexOf("File ID");
  const resultIndex = headers.indexOf("Result");
  const statusIndex = headers.indexOf("Status");

  if ([commandIndex, fileIdIndex, resultIndex, statusIndex].some(function(index) {
    return index === -1;
  })) {
    throw new Error("FILE_ID_PERSISTENCE_COLUMNS_INVALID");
  }

  let repaired = 0;

  for (let i = 1; i < data.length; i++) {
    const row = data[i];
    const command = String(row[commandIndex] || "").trim().toUpperCase();
    const existingFileId = String(row[fileIdIndex] || "").trim();
    const status = String(row[statusIndex] || "").trim().toUpperCase();

    if (command !== "CREATE_FILE" || existingFileId || status !== "COMPLETED") {
      continue;
    }

    let result;
    try {
      result = JSON.parse(String(row[resultIndex] || ""));
    } catch (error) {
      continue;
    }

    if (!result || !result.fileId || result.verified !== true) {
      continue;
    }

    sheet.getRange(i + 1, fileIdIndex + 1).setValue(String(result.fileId));

    const readBack = String(
      sheet.getRange(i + 1, fileIdIndex + 1).getValue() || ""
    ).trim();

    if (readBack !== String(result.fileId).trim()) {
      throw new Error("FILE_ID_PERSISTENCE_REPAIR_VERIFICATION_FAILED");
    }

    repaired++;
  }

  return {
    status: "FILE_ID_PERSISTENCE_REPAIR_COMPLETED",
    verified: true,
    repaired: repaired,
    timestamp: new Date().toISOString()
  };
}
