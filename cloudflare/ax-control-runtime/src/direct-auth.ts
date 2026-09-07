export const directSessionTokenAccepted = {
  async create(issuedAt: number, nonce: string, secret: string): Promise<string> {
    const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
    const signature = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(`${issuedAt}.${nonce}`));
    let binary = '';
    for (const byte of new Uint8Array(signature)) binary += String.fromCharCode(byte);
    const encoded = btoa(binary).replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '');
    return `${issuedAt}.${nonce}.${encoded}`;
  },
  async verify(token: string, secret: string, now = Date.now()): Promise<boolean> {
    const parts = token.split('.');
    if (parts.length !== 3) return false;
    const issuedAt = Number(parts[0]);
    if (!Number.isFinite(issuedAt) || issuedAt <= 0 || now - issuedAt > 30 * 60 * 1000 || now < issuedAt - 60_000) return false;
    const expected = await this.create(issuedAt, parts[1], secret);
    const a = new TextEncoder().encode(parts[2]);
    const b = new TextEncoder().encode(expected.split('.')[2]);
    if (a.length !== b.length) return false;
    let diff = 0;
    for (let i = 0; i < a.length; i += 1) diff |= a[i] ^ b[i];
    return diff === 0;
  },
};
