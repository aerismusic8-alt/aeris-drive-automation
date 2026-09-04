const $ = (id) => document.getElementById(id);

function token() { return sessionStorage.getItem('ax_gateway_token') || ''; }
function setAuth(value) { if (value) sessionStorage.setItem('ax_gateway_token', value); else sessionStorage.removeItem('ax_gateway_token'); }
function newId(prefix) { return `${prefix}-${crypto.randomUUID()}`; }

async function api(path, options = {}) {
  const headers = { ...(options.headers || {}) };
  if (options.body && !headers['Content-Type']) headers['Content-Type'] = 'application/json';
  if (token()) headers.Authorization = `Bearer ${token()}`;
  const response = await fetch(path, { ...options, headers });
  const data = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(data.error_code || `HTTP_${response.status}`);
  return data;
}

function showAuthenticated() {
  $('authForm').classList.add('hidden'); $('controls').classList.remove('hidden'); $('chatPanel').classList.remove('hidden');
}
function showContext(data) {
  $('session').textContent = data.session_status || 'UNKNOWN';
  $('identity').textContent = data.identity || '—';
  $('rehydration').textContent = data.rehydration_status || '—';
  $('context').textContent = JSON.stringify({source_of_truth:data.source_of_truth, state_version:data.state_version, caller_identity:data.caller_identity, model_independence:data.model_independence}, null, 2);
}

async function hydrate() {
  const session = await api('/gateway/session');
  showContext(session);
  const capabilities = await api('/gateway/capabilities');
  if (!capabilities.capabilities.includes('submit_input')) throw new Error('CAPABILITY_DENIED');
  await api('/gateway/state');
  showAuthenticated();
}

$('login').onclick = async () => {
  try {
    const result = await api('/auth/login', {method:'POST', body:JSON.stringify({username:$('username').value,password:$('password').value})});
    setAuth(result.token); await hydrate();
  } catch (error) { $('session').textContent = error.message; }
};

$('refresh').onclick = async () => { try { showContext(await api('/gateway/session')); } catch (error) { $('session').textContent = error.message; } };
$('check').onclick = async () => { try { $('context').textContent = JSON.stringify(await api('/gateway/m-a-check',{method:'POST',body:'{}'}),null,2); } catch (error) { $('context').textContent = error.message; } };
$('logout').onclick = async () => { try { await api('/auth/logout',{method:'POST',body:'{}'}); } finally { setAuth(''); location.reload(); } };

$('send').onclick = async () => {
  try {
    const files = [...$('file').files].map((file) => ({attachment_id:newId('att'),kind:file.type.startsWith('image/')?'image':'file',name:file.name,media_type:file.type||'application/octet-stream',reference:`browser:${crypto.randomUUID()}`}));
    const payload = {request_id:newId('req'),idempotency_key:newId('idem'),source_channel:'WEB',content_type:files.length?(files.some((item)=>item.kind==='image')?'image':'file'):'text',content:$('message').value,attachments:files};
    const result = await api('/gateway/input',{method:'POST',body:JSON.stringify(payload)});
    $('messages').textContent += `\n\n[${result.status}] ${result.request_id}\n${result.content || ''}`;
    $('result').textContent = JSON.stringify(result,null,2);
    $('message').value=''; $('file').value='';
  } catch (error) { $('result').textContent = error.message; }
};

if (token()) hydrate().catch(() => { setAuth(''); });
