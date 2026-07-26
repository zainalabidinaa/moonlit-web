import type { Transition } from 'framer-motion';

function spring(response: number, dampingFraction: number): Transition {
  const stiffness = Math.pow((2 * Math.PI) / response, 2);
  const damping = (4 * Math.PI * dampingFraction) / response;
  return { type: 'spring', stiffness, damping, mass: 1 };
}

export const SPRING = {
  tileHover: spring(0.30, 0.78),
  nav: spring(0.30, 0.75),
  heroStep: spring(0.42, 0.82),
  continueWatching: spring(0.28, 0.78),
  panel: spring(0.40, 0.85),
} as const;

export const EASE = {
  heroCrossfade: { duration: 0.40, ease: 'easeInOut' },
  ambientColor: { duration: 0.9, ease: 'easeInOut' },
  panelSlide: { duration: 0.22, ease: 'easeOut' },
} as const;

export const TILE_HOVER_SCALE = 1.04;
