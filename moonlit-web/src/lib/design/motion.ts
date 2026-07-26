import type { Transition } from 'framer-motion';

function spring(response: number, dampingFraction: number): Transition {
  const stiffness = Math.pow((2 * Math.PI) / response, 2);
  const damping = (4 * Math.PI * dampingFraction) / response;
  return { type: 'spring', stiffness, damping, mass: 1 };
}

export const SPRING = {
  cardHover: spring(0.28, 0.78),
  nav: spring(0.25, 0.75),
  panel: spring(0.35, 0.85),
} as const;

export const EASE = {
  heroCrossfade: { duration: 0.5, ease: 'easeInOut' },
  ambientColor: { duration: 1.2, ease: 'easeInOut' },
  pillHighlight: { duration: 0.15, ease: 'easeInOut' },
  panelSlide: { duration: 0.2, ease: 'easeOut' },
  controlsFade: { duration: 0.18, ease: 'easeInOut' },
} as const;

export const TILE_HOVER_SCALE = 1.12;
