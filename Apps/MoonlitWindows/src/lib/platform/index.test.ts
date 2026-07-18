import { describe, it, expect, afterEach } from 'vitest';
import { isDesktop } from './index';

describe('isDesktop', () => {
  afterEach(() => {
    delete (window as unknown as Record<string, unknown>).__TAURI_INTERNALS__;
  });

  it('returns false in a plain browser', () => {
    expect(isDesktop()).toBe(false);
  });

  it('returns true when Tauri internals are present', () => {
    (window as unknown as Record<string, unknown>).__TAURI_INTERNALS__ = {};
    expect(isDesktop()).toBe(true);
  });
});
