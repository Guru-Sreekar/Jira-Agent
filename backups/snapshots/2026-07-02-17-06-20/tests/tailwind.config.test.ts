import type { Config } from 'tailwindcss';

// Type declaration for jest when @jest/globals types are not available
declare const jest: {
  mock: (moduleName: string, factory: () => unknown) => void;
  requireActual: <T = unknown>(moduleName: string) => T;
};

// Mock the config module
jest.mock('../tailwind.config', () => {
  const actualConfig = jest.requireActual<typeof import('../tailwind.config')>('../tailwind.config');
  return actualConfig;
});

// Import the config after mocking
import config from '../tailwind.config';

describe('tailwind.config.ts', () => {
  describe('config structure', () => {
    it('should export a valid Tailwind config object', () => {
      expect(config).toBeDefined();
      expect(typeof config).toBe('object');
      expect(config).not.toBeNull();
    });

    it('should have correct darkMode setting', () => {
      expect(config.darkMode).toBe('class');
    });

    it('should have content array with correct paths', () => {
      expect(Array.isArray(config.content)).toBe(true);
      expect(config.content).toHaveLength(3);
      expect(config.content).toEqual([
        './src/pages/**/*.{js,ts,jsx,tsx,mdx}',
        './src/components/**/*.{js,ts,jsx,tsx,mdx}',
        './src/app/**/*.{js,ts,jsx,tsx,mdx}',
      ]);
    });

    it('should have theme.extend.colors defined', () => {
      expect(config.theme).toBeDefined();
      expect(config.theme.extend).toBeDefined();
      expect(config.theme.extend.colors).toBeDefined();
    });

    it('should have empty plugins array', () => {
      expect(Array.isArray(config.plugins)).toBe(true);
      expect(config.plugins).toHaveLength(0);
    });
  });

  describe('color configuration', () => {
    const colors = config.theme.extend.colors;

    it('should have background color with HSL variable', () => {
      expect(colors.background).toBe('hsl(var(--background))');
    });

    it('should have foreground color with HSL variable', () => {
      expect(colors.foreground).toBe('hsl(var(--foreground))');
    });

    it('should have card color with DEFAULT and foreground variants', () => {
      expect(colors.card).toBeDefined();
      expect(colors.card.DEFAULT).toBe('hsl(var(--card))');
      expect(colors.card.foreground).toBe('hsl(var(--card-foreground))');
    });

    it('should have popover color with DEFAULT and foreground variants', () => {
      expect(colors.popover).toBeDefined();
      expect(colors.popover.DEFAULT).toBe('hsl(var(--popover))');
      expect(colors.popover.foreground).toBe('hsl(var(--popover-foreground))');
    });

    it('should have primary color with DEFAULT and foreground variants', () => {
      expect(colors.primary).toBeDefined();
      expect(colors.primary.DEFAULT).toBe('hsl(var(--primary))');
      expect(colors.primary.foreground).toBe('hsl(var(--primary-foreground))');
    });

    it('should have secondary color with DEFAULT and foreground variants', () => {
      expect(colors.secondary).toBeDefined();
      expect(colors.secondary.DEFAULT).toBe('hsl(var(--secondary))');
      expect(colors.secondary.foreground).toBe('hsl(var(--secondary-foreground))');
    });

    it('should have muted color with DEFAULT and foreground variants', () => {
      expect(colors.muted).toBeDefined();
      expect(colors.muted.DEFAULT).toBe('hsl(var(--muted))');
      expect(colors.muted.foreground).toBe('hsl(var(--muted-foreground))');
    });

    it('should have accent color with DEFAULT and foreground variants', () => {
      expect(colors.accent).toBeDefined();
      expect(colors.accent.DEFAULT).toBe('hsl(var(--accent))');
      expect(colors.accent.foreground).toBe('hsl(var(--accent-foreground))');
    });

    it('should have destructive color with DEFAULT and foreground variants', () => {
      expect(colors.destructive).toBeDefined();
      expect(colors.destructive.DEFAULT).toBe('hsl(var(--destructive))');
      expect(colors.destructive.foreground).toBe('hsl(var(--destructive-foreground))');
    });

    it('should have border, input, and ring colors', () => {
      expect(colors.border).toBe('hsl(var(--border))');
      expect(colors.input).toBe('hsl(var(--input))');
      expect(colors.ring).toBe('hsl(var(--ring))');
    });
  });

  describe('dark mode support', () => {
    it('should have darkMode set to class strategy', () => {
      expect(config.darkMode).toBe('class');
    });

    it('should have content paths that include all source directories', () => {
      expect(config.content).toContain('./src/**/*.{js,ts,jsx,tsx,mdx}');
    });
  });
});

