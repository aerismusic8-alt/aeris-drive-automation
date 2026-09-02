const API_BASE = "https://script.googleapis.com/v1/projects";

async function request(url, accessToken, options = {}) {
  const response = await fetch(url, {
    ...options,
    headers: {
      Authorization: `Bearer ${accessToken}`,
      "Content-Type": "application/json",
      ...(options.headers || {}),
    },
  });

  const text = await response.text();
  let body;
  try { body = text ? JSON.parse(text) : null; } catch { body = text; }

  if (!response.ok) {
    const error = new Error(`APPS_SCRIPT_API_${response.status}`);
    error.status = response.status;
    error.body = body;
    throw error;
  }
  return body;
}

export function assertScriptId(scriptId) {
  if (!scriptId || !/^[A-Za-z0-9_-]{10,}$/.test(scriptId)) {
    throw new Error("APPS_SCRIPT_ID_REQUIRED");
  }
}

export async function getProjectContent(scriptId, accessToken) {
  assertScriptId(scriptId);
  if (!accessToken) throw new Error("OAUTH_ACCESS_TOKEN_REQUIRED");
  return request(`${API_BASE}/${encodeURIComponent(scriptId)}/content`, accessToken);
}

export async function updateProjectContent(scriptId, accessToken, content) {
  assertScriptId(scriptId);
  if (!accessToken) throw new Error("OAUTH_ACCESS_TOKEN_REQUIRED");
  if (!content || !Array.isArray(content.files) || content.files.length === 0) {
    throw new Error("COMPLETE_PROJECT_CONTENT_REQUIRED");
  }
  const hasManifest = content.files.some((file) => file.name === "appsscript" && file.type === "JSON");
  if (!hasManifest) throw new Error("APPSCRIPT_MANIFEST_REQUIRED");
  return request(`${API_BASE}/${encodeURIComponent(scriptId)}/content`, accessToken, {
    method: "PUT",
    body: JSON.stringify(content),
  });
}

export async function listDeployments(scriptId, accessToken) {
  assertScriptId(scriptId);
  if (!accessToken) throw new Error("OAUTH_ACCESS_TOKEN_REQUIRED");
  return request(`${API_BASE}/${encodeURIComponent(scriptId)}/deployments`, accessToken);
}
