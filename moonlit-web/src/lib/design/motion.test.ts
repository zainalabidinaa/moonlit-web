import { describe, expect, it } from 'vitest';

import * as motion from './motion';

type HeroTransition = (
  source: 'manual' | 'automatic',
  reducedMotion: boolean,
) => { type?: string; stiffness?: number; damping?: number; mass?: number; duration?: number };

describe('Mac hero motion contract', () => {
  it('uses response 0.42 for manual changes, 0.50 for automatic changes, damping 0.82, and no spring under reduced motion', () => {
    const heroTransition = (motion as { heroTransition?: HeroTransition }).heroTransition;
    expect(heroTransition).toBeTypeOf('function');
    if (!heroTransition) return;

    const manual = heroTransition('manual', false);
    const automatic = heroTransition('automatic', false);

    expect(manual).toMatchObject({ type: 'spring', mass: 1 });
    expect(manual.stiffness).toBeCloseTo(Math.pow((2 * Math.PI) / 0.42, 2), 5);
    expect(manual.damping).toBeCloseTo((4 * Math.PI * 0.82) / 0.42, 5);
    expect(automatic.stiffness).toBeCloseTo(Math.pow((2 * Math.PI) / 0.5, 2), 5);
    expect(automatic.damping).toBeCloseTo((4 * Math.PI * 0.82) / 0.5, 5);
    expect(heroTransition('automatic', true)).toEqual({ duration: 0 });
  });
});
