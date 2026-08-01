import type { Transition } from 'framer-motion';
import { motionTokens } from './tokens';

function spring(response: number, dampingFraction: number): Transition {
  const stiffness = Math.pow((2 * Math.PI) / response, 2);
  const damping = (4 * Math.PI * dampingFraction) / response;
  return { type: 'spring', stiffness, damping, mass: 1 };
}

export const SPRING = {
  cardHover: spring(motionTokens.cardSpring.response, motionTokens.cardSpring.dampingFraction),
  nav: spring(0.25, 0.75),
  panel: spring(motionTokens.rowSpring.response, motionTokens.rowSpring.dampingFraction),
  heroManual: spring(motionTokens.heroManualSpring.response, motionTokens.heroManualSpring.dampingFraction),
  heroAutomatic: spring(motionTokens.heroAutomaticSpring.response, motionTokens.heroAutomaticSpring.dampingFraction),
} as const;

export type HeroTransitionSource = 'manual' | 'automatic';

export function heroTransition(source: HeroTransitionSource, reducedMotion: boolean): Transition {
  if (reducedMotion) return { duration: 0 };
  return source === 'automatic' ? SPRING.heroAutomatic : SPRING.heroManual;
}

export const EASE = {
  heroCrossfade: { duration: motionTokens.heroCrossfade, ease: 'easeInOut' },
  ambientColor: { duration: motionTokens.ambientColor, ease: 'easeInOut' },
  pillHighlight: { duration: motionTokens.fast, ease: 'easeInOut' },
  panelSlide: { duration: 0.2, ease: 'easeOut' },
  controlsFade: { duration: motionTokens.controls, ease: 'easeInOut' },
} as const;

export const TILE_HOVER_SCALE = 1.04;
