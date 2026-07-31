import { fireEvent, render, screen } from '@testing-library/react';
import fs from 'node:fs/promises';
import path from 'node:path';
import postcss from 'postcss';
import tailwindcss from 'tailwindcss';
import { beforeAll, describe, expect, it, vi } from 'vitest';

import ProfilesPage from '@/routes/profiles';

vi.mock('@/app/AuthProvider', () => ({
  useAuth: () => ({
    profiles: [],
    currentProfile: null,
    selectProfile: vi.fn(),
    createProfile: vi.fn(async () => undefined),
    deleteProfile: vi.fn(async () => undefined),
    signOut: vi.fn(async () => undefined),
  }),
}));

vi.mock('@tanstack/react-router', () => ({
  useNavigate: () => vi.fn(),
}));

let compiledCss: postcss.Root;

function rgbChannels(color: string): [number, number, number] {
  const channels = color.match(/[\d.]+/g)?.slice(0, 3).map(Number);
  if (!channels || channels.length !== 3) throw new Error(`Expected an RGB color, received ${color}`);
  return channels as [number, number, number];
}

function contrastRatio(foreground: [number, number, number], background: [number, number, number]): number {
  const luminance = (channels: [number, number, number]) => {
    const linear = channels.map(channel => {
      const value = channel / 255;
      return value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4;
    });
    return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2];
  };
  const lighter = Math.max(luminance(foreground), luminance(background));
  const darker = Math.min(luminance(foreground), luminance(background));
  return (lighter + 0.05) / (darker + 0.05);
}

function compiledColors(element: Element) {
  const variables = new Map<string, string>();
  const properties = new Map<string, string>();
  const classes = [...element.classList];
  let inheritedColor = '#FFFFFF';

  compiledCss.walkRules(rule => {
    if (rule.selector !== ':root') return;
    rule.walkDecls(declaration => variables.set(declaration.prop, declaration.value));
  });

  compiledCss.walkRules(rule => {
    if (rule.selector !== 'body') return;
    rule.walkDecls('color', declaration => { inheritedColor = declaration.value; });
  });

  compiledCss.walkRules(rule => {
    const selectors = rule.selectors ?? [];
    if (!classes.some(className => selectors.includes(`.${className}`))) return;
    rule.walkDecls(declaration => {
      properties.set(declaration.prop, declaration.value);
      if (declaration.prop.startsWith('--')) variables.set(declaration.prop, declaration.value);
      if (declaration.prop === 'background') properties.delete('background-color');
      if (declaration.prop === 'background-color') properties.delete('background');
    });
  });

  const resolveVariables = (input: string) => {
    let output = input;
    for (let pass = 0; pass < 4 && output.includes('var('); pass += 1) {
      output = output.replace(/var\((--[\w-]+)(?:,\s*([^)]+))?\)/g, (_match, name: string, fallback: string | undefined) => (
        variables.get(name) ?? fallback ?? ''
      ));
    }
    return output;
  };
  const parseColor = (input: string): [number, number, number] => {
    const resolved = resolveVariables(input).trim();
    if (/^#[0-9a-f]{3}$/i.test(resolved)) {
      return [1, 2, 3].map(index => Number.parseInt(resolved[index] + resolved[index], 16)) as [number, number, number];
    }
    if (/^#[0-9a-f]{6}$/i.test(resolved)) {
      return [1, 3, 5].map(index => Number.parseInt(resolved.slice(index, index + 2), 16)) as [number, number, number];
    }
    return rgbChannels(resolved);
  };

  return {
    foreground: parseColor(properties.get('color') ?? inheritedColor),
    background: parseColor(properties.get('background-color') ?? properties.get('background') ?? '#000000'),
  };
}

function expectReadable(element: Element) {
  const colors = compiledColors(element);
  expect(contrastRatio(colors.foreground, colors.background)).toBeGreaterThanOrEqual(4.5);
}

describe('semantic action and selection colors', () => {
  beforeAll(async () => {
    const configModule = await import('../../../tailwind.config.js');
    const config = {
      ...configModule.default,
      content: [{
        raw: '<button class="category-pill category-pill-active btn-primary bg-moonlit-action text-moonlit-action-foreground"></button>',
        extension: 'html',
      }],
    };
    const sourcePath = path.resolve(process.cwd(), 'src/index.css');
    const source = await fs.readFile(sourcePath, 'utf8');
    const result = await postcss([tailwindcss(config)]).process(source, { from: sourcePath });
    compiledCss = postcss.parse(result.css);
  });

  it('keeps active category pills readable with a distinct selection treatment', () => {
    const pill = document.createElement('button');
    pill.className = 'category-pill category-pill-active';
    document.body.append(pill);

    expectReadable(pill);
    expect(compiledColors(pill).background).not.toEqual([255, 255, 255]);
    pill.remove();
  });

  it('keeps the profile create action readable on the white Mac accent', () => {
    render(<ProfilesPage />);
    fireEvent.click(screen.getByRole('button', { name: /Add Profile/ }));

    expectReadable(screen.getByRole('button', { name: 'Create' }));
  });

  it('keeps the browse primary CTA intentionally white with a dark foreground', () => {
    const action = document.createElement('button');
    action.className = 'btn-primary';
    document.body.append(action);

    expect(compiledColors(action).background).toEqual([255, 255, 255]);
    expectReadable(action);
    action.remove();
  });
});
