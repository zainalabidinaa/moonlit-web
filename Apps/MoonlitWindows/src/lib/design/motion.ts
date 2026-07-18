/// Mac spring presets translated to framer-motion transitions.
/// SwiftUI spring(response, dampingFraction) ↔ stiffness/damping (mass 1):
///   stiffness = (2π / response)²
///   damping   = 4π · dampingFraction / response
import type { Transition } from 'framer-motion';

function spring(response: number, dampingFraction: number): Transition {
  const stiffness = Math.pow((2 * Math.PI) / response, 2);
  const damping = (4 * Math.PI * dampingFraction) / response;
  return { type: 'spring', stiffness, damping, mass: 1 };
}

export const SPRING = {
  /** MediaCard / FolderTile / channel tile hover — scale 1.04 */
  tileHover: spring(0.30, 0.78),
  /** Hero manual step */
  heroStep: spring(0.42, 0.82),
  /** Hero auto-advance */
  heroAuto: spring(0.50, 0.82),
  /** Pill nav tab switching / search hover */
  nav: spring(0.30, 0.75),
  /** Library save toggle */
  libraryToggle: spring(0.25, 0.60),
  /** Continue watching card hover */
  continueWatching: spring(0.28, 0.78),
  /** Player panels / toasts */
  panel: spring(0.40, 0.85),
  /** Detail rows hover */
  detailRow: spring(0.28, 0.82),
} as const;

export const EASE = {
  heroCrossfade: { duration: 0.35, ease: 'easeInOut' },
  ambientColor: { duration: 0.9, ease: 'easeInOut' },
  categoryPill: { duration: 0.18, ease: 'easeInOut' },
  pillHighlight: { duration: 0.15, ease: 'easeInOut' },
  searchExpand: { duration: 0.2, ease: 'easeOut' },
  haloResolve: { duration: 0.3, ease: 'easeOut' },
  panelSlide: { duration: 0.22, ease: 'easeOut' },
  controlsFade: { duration: 0.18, ease: 'easeInOut' },
} as const;

/** Hover scale used across Mac tiles. */
export const TILE_HOVER_SCALE = 1.04;
