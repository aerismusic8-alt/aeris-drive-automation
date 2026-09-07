import { describe, expect, it } from 'vitest';
import { directSessionTokenAccepted } from '../src/direct-auth';

describe('AX direct auth', () => {
  it('accepts a valid web session token for direct channel requests', async () => {
    const secret = 'test-secret';
    const issuedAt = Date.now();
    const nonce = 'nonce-1';
    const token = await directSessionTokenAccepted.create(issuedAt, nonce, secret);
    await expect(directSessionTokenAccepted.verify(token, secret, issuedAt + 1000)).resolves.toBe(true);
  });
});
