# File ID Persistence Acceptance

The File ID Persistence gate requires a stable logical file ID independent of model/runtime process state.

Acceptance criteria:
- stable logical ID survives fresh-process reconstruction;
- ID resolves to the canonical path;
- content hash mismatch invalidates verification;
- duplicate IDs fail closed;
- persistence contains no secrets;
- evidence identifies the persisted ID and verification result.

A gate may be marked VERIFIED only after an executable test produces evidence for all criteria.
