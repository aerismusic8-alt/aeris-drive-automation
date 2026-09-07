import { describe, expect, test } from 'vitest';
import { axDirectConsolePage } from '../src/ax-direct-console';

describe('AX Direct Console chat UX', () => {
  test('renders a simple chat composer with Enter send and image/video attachment support', async () => {
    const response = axDirectConsolePage();
    const html = await response.text();

    expect(html).toContain('<textarea');
    expect(html).toContain('keydown');
    expect(html).toContain("e.key==='Enter'");
    expect(html).toContain('type="file"');
    expect(html).toContain('accept="image/*,video/*"');
    expect(html).not.toContain('fingerprint');
    expect(html).not.toContain('transport:');
  });
});
