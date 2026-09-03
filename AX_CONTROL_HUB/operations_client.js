const $ = (id) => document.getElementById(id);

function token() {
  return localStorage.getItem('ax_gateway_token') || '';
}

async function api(path, options = {}) {
  const headers = { ...(options.headers || {}) };
  if (options.body && !headers['Content-Type']) headers['Content-Type'] = 'application/json';
  if (token()) headers.Authorization = `Bearer ${token()}`;
  const response = await fetch(path, { ...options, headers });
  const data = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(data.error_code || `HTTP_${response.status}`);
  return data;
}

$('login').onclick = async () => {
  const result = await api('/auth/login', {
    method: 'POST',
    body: JSON.stringify({ username: $('username').value, password: $('password').value })
  });
  localStorage.setItem('ax_gateway_token', result.token);
  $('state').textContent = 'AUTHENTICATED';
};

$('check').onclick = async () => {
  try {
    const result = await api('/gateway/m-a-check', { method: 'POST', body: '{}' });
    $('state').textContent = JSON.stringify(result, null, 2);
  } catch (error) {
    $('state').textContent = error.message;
  }
};

$('send').onclick = async () => {
  try {
    const files = [...$('file').files].map((file) => ({
      attachment_id: crypto.randomUUID(),
      kind: file.type.startsWith('image/') ? 'image' : 'file',
      name: file.name,
      media_type: file.type || 'application/octet-stream',
      reference: `browser:${crypto.randomUUID()}`
    }));
    const payload = {
      source_channel: 'MOBILE',
      content_type: files.length ? (files.some((item) => item.kind === 'image') ? 'image' : 'file') : 'text',
      content: $('message').value,
      attachments: files
    };
    $('result').textContent = JSON.stringify(await api('/gateway/input', {
      method: 'POST',
      body: JSON.stringify(payload)
    }), null, 2);
  } catch (error) {
    $('result').textContent = error.message;
  }
};
