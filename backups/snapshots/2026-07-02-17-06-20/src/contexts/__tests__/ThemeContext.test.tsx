import React from "react";
import { render, screen, fireEvent } from "@testing-library/react";
import { ThemeProvider, useTheme } from "@/contexts/ThemeContext";
import "@testing-library/jest-dom";
import { act } from "react";

// Install dependencies if missing:
// npm install --save-dev @testing-library/react @testing-library/jest-dom

// Ensure dependencies are installed:
// Run: npm install --save-dev @testing-library/react @testing-library/jest-dom

// Mock localStorage
const localStorageMock = (() => {
  let store: Record<string, string> = {};
  return {
    getItem: jest.fn((key: string) => store[key] || null),
    setItem: jest.fn((key: string, value: string) => {
      store[key] = value;
    }),
    removeItem: jest.fn((key: string) => {
      delete store[key];
    }),
    clear: jest.fn(() => {
      store = {};
    }),
  };
})();

Object.defineProperty(window, "localStorage", {
  value: localStorageMock,
});

// Mock matchMedia
Object.defineProperty(window, "matchMedia", {
  writable: true,
  value: jest.fn().mockImplementation((query: string) => ({
    matches: false,
    media: query,
    onchange: null,
    addListener: jest.fn(),
    removeListener: jest.fn(),
    addEventListener: jest.fn(),
    removeEventListener: jest.fn(),
    dispatchEvent: jest.fn(),
  })),
});

function TestComponent() {
  const { theme, toggleTheme, setTheme } = useTheme();
  return (
    <div>
      <span data-testid="theme">{theme}</span>
      <button data-testid="toggle" onClick={toggleTheme}>
        Toggle
      </button>
      <button data-testid="set-dark" onClick={() => setTheme("dark")}>
        Set Dark
      </button>
      <button data-testid="set-light" onClick={() => setTheme("light")}>
        Set Light
      </button>
    </div>
  );
}

describe("ThemeContext", () => {
  beforeEach(() => {
    localStorageMock.clear();
    jest.clearAllMocks();
  });

  describe("system preference detection", () => {
    it("should default to light when no stored preference and system prefers light", () => {
      window.matchMedia = jest.fn().mockImplementation((query: string) => ({
        matches: false,
        media: query,
        onchange: null,
        addListener: jest.fn(),
        removeListener: jest.fn(),
        addEventListener: jest.fn(),
        removeEventListener: jest.fn(),
        dispatchEvent: jest.fn(),
      }));

      render(
        <ThemeProvider>
          <TestComponent />
        </ThemeProvider>
      );

      expect(screen.getByTestId("theme").textContent).toBe("light");
    });

    it("should default to dark when no stored preference and system prefers dark", () => {
      window.matchMedia = jest.fn().mockImplementation((query: string) => ({
        matches: query === "(prefers-color-scheme: dark)",
        media: query,
        onchange: null,
        addListener: jest.fn(),
        removeListener: jest.fn(),
        addEventListener: jest.fn(),
        removeEventListener: jest.fn(),
        dispatchEvent: jest.fn(),
      }));

      render(
        <ThemeProvider>
          <TestComponent />
        </ThemeProvider>
      );

      expect(screen.getByTestId("theme").textContent).toBe("dark");
    });
  });

  describe("localStorage persistence", () => {
    it("should use stored theme from localStorage if available", () => {
      localStorageMock.setItem("theme-preference", "dark");

      render(
        <ThemeProvider>
          <TestComponent />
        </ThemeProvider>
      );

      expect(screen.getByTestId("theme").textContent).toBe("dark");
    });

    it("should persist theme to localStorage when toggled", () => {
      render(
        <ThemeProvider>
          <TestComponent />
        </ThemeProvider>
      );

      act(() => {
        fireEvent.click(screen.getByTestId("toggle"));
      });

      expect(localStorageMock.setItem).toHaveBeenCalledWith(
        "theme-preference",
        "dark"
      );
    });
  });

  describe("toggling behavior", () => {
    it("should toggle from light to dark", () => {
      render(
        <ThemeProvider>
          <TestComponent />
        </ThemeProvider>
      );

      expect(screen.getByTestId("theme").textContent).toBe("light");

      act(() => {
        fireEvent.click(screen.getByTestId("toggle"));
      });

      expect(screen.getByTestId("theme").textContent).toBe("dark");
    });

    it("should toggle from dark to light", () => {
      localStorageMock.setItem("theme-preference", "dark");

      render(
        <ThemeProvider>
          <TestComponent />
        </ThemeProvider>
      );

      expect(screen.getByTestId("theme").textContent).toBe("dark");

      act(() => {
        fireEvent.click(screen.getByTestId("toggle"));
      });

      expect(screen.getByTestId("theme").textContent).toBe("light");
    });

    it("should set theme directly with setTheme", () => {
      render(
        <ThemeProvider>
          <TestComponent />
        </ThemeProvider>
      );

      act(() => {
        fireEvent.click(screen.getByTestId("set-dark"));
      });

      expect(screen.getByTestId("theme").textContent).toBe("dark");
    });
  });

  describe("document class management", () => {
    it("should apply dark class to document element when theme is dark", () => {
      localStorageMock.setItem("theme-preference", "dark");

      render(
        <ThemeProvider>
          <TestComponent />
        </ThemeProvider>
      );

      expect(document.documentElement.classList.contains("dark")).toBe(true);
      expect(document.documentElement.classList.contains("light")).toBe(false);
    });

    it("should apply light class to document element when theme is light", () => {
      render(
        <ThemeProvider>
          <TestComponent />
        </ThemeProvider>
      );

      expect(document.documentElement.classList.contains("light")).toBe(true);
      expect(document.documentElement.classList.contains("dark")).toBe(false);
    });
  });

  describe("error handling", () => {
    it("should throw error when useTheme is used outside ThemeProvider", () => {
      function BadComponent() {
        useTheme();
        return null;
      }

      expect(() => {
        render(<BadComponent />);
      }).toThrow("useTheme must be used within a ThemeProvider");
    });
  });
});

