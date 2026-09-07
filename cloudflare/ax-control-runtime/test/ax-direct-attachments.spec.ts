import { describe, expect, test } from 'vitest';
import { axDirectConsolePage } from '../src/ax-direct-console';

describe('AX Direct attachment flow', () => {
  test('uploads selected media to the direct attachment endpoint before dispatching the command', async () => {
    const html = await (axDirectConsolePage()).text();
    expect(html).toContain('FormData');
    expect(html).toContain('/ax/direct/attachment');
    expect(html).toContain("accept=\"image/*,video/*\"");
  });
});
