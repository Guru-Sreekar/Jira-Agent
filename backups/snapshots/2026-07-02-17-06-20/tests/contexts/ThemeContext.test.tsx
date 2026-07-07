import React from "react";
import { render, screen, act } from "@testing-library/react";
import { ThemeProvider, useTheme } from "@/contexts/ThemeContext";

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
const matchMediaMock = jest.fn().mockImplementation((query: string) => ({
  matches: false,
  media: query,
  onchange: null,
  addListener: jest.fn(),
  removeListener: jest.fn(),
  addEventListener: jest.fn(),
  removeEventListener: jest.fn(),
  dispatchEvent: jest.fn(),
}));

Object.defineProperty(window, "matchMedia", {
  value: matchMediaMock,
});

// Helper component to test the hook
const TestComponent: React.FC<{ onThemeChange?: (theme: string) => void }> = ({ onThemeChange }) => {
  const { theme, toggleTheme, setTheme } = useTheme();
  
  React.useEffect(() => {
    if (onThemeChange) {
      onThemeChange(theme);
    }
  }, [theme, onThemeChange]);
  
  return (
    <div>
      <span data-testid="theme">{theme}</span>
      <button data-testid="toggle" onClick={toggleTheme}>Toggle</button>
      <button data-testid="set-light" onClick={() => setTheme("light")}>Set Light</button>
      <button data-testid="set-dark" onClick={() => setTheme("dark")}>Set Dark</button>
    </div>
  );
};

// Helper component to test hook error
const TestComponentWithoutProvider: React.FC = () => {
  useTheme();
  return <div>Should not render</div>;
};

describe("ThemeContext", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    localStorageMock.clear();
    document.documentElement.className = "";
  });

  describe("ThemeProvider", () => {
    it("should render children after mounting", () => {
      render(
        <ThemeProvider>
          <div data-testid="child">Child Content</div>
        </ThemeProvider>
      );
      
      expect(screen.getByTestId("child")).toBeInTheDocument();
    });

    it("should not render children before mounting (prevent hydration mismatch)", () => {
      const { container } = render(
        <ThemeProvider>
          <div data-testid="child">Child Content</div>
        </ThemeProvider>
      );
      
      // After mounting, children should be rendered
      expect(container.querySelector("[data-testid='child']")).toBeInTheDocument();
    });

    it("should initialize with light theme by default", () => {
      render(
        <ThemeProvider>
          <TestComponent />
        </ThemeProvider>
      );
      
      expect(screen.getByTestId("theme")).toHaveTextContent("light");
    });

    it("should initialize with dark theme when system prefers dark", () => {
      matchMediaMock.mockImplementation((query: string) => ({
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
      
      expect(screen.getByTestId("theme")).toHaveTextContent("dark");
    });

    it("should use stored theme preference over system preference", () => {
      localStorageMock.setItem("theme-preference", "dark");
      matchMediaMock.mockImplementation((query: string) => ({
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
      
      expect(screen.getByTestId("theme")).toHaveTextContent("dark");
    });

    it("should use stored light theme preference", () => {
      localStorageMock.setItem("theme-preference", "light");
      
      render(
        <ThemeProvider>
          <TestComponent />
        </ThemeProvider>
      );
      
      expect(screen.getByTestId("theme")).toHaveTextContent("light");
    });

    it("should ignore invalid stored theme values", () => {
      localStorageMock.setItem("theme-preference", "invalid-theme");
      
      render(
        <ThemeProvider>
          <TestComponent />
        </ThemeProvider>
      );
      
      // Should fall back to system preference (light by default)
      expect(screen.getByTestId("theme")).toHaveTextContent("light");
    });

    it("should handle localStorage being unavailable", () => {
      const originalLocalStorage = window.localStorage;
      Object.defineProperty(window, "localStorage", {
        value: undefined,
        writable: true,
      });
      
      expect(() => {
        render(
          <ThemeProvider>
            <TestComponent />
          </ThemeProvider>
        );
      }).not.toThrow();
      
      expect(screen.getByTestId("theme")).toHaveTextContent("light");
      
      // Restore localStorage
      Object.defineProperty(window, "localStorage", {
        value: originalLocalStorage,
        writable: true,
      });
    });

    it("should handle localStorage getItem throwing an error", () => {
      const originalGetItem = localStorageMock.getItem;
      localStorageMock.getItem.mockImplementation(() => {
        throw new Error("localStorage not available");
      });
      
      expect(() => {
        render(
          <ThemeProvider>
            <TestComponent />
          </ThemeProvider>
        );
      }).not.toThrow();
      
      expect(screen.getByTestId("theme")).toHaveTextContent("light");
      
      // Restore
      localStorageMock.getItem = originalGetItem;
    });

    it("should handle localStorage setItem throwing an error", () => {
      const originalSetItem = localStorageMock.setItem;
      localStorageMock.setItem.mockImplementation(() => {
        throw new Error("localStorage not available");
      });
      
      expect(() => {
        render(
          <ThemeProvider>
            <TestComponent />
          </ThemeProvider>
        );
      }).not.toThrow();
      
      // Restore
      localStorageMock.setItem = originalSetItem;
    });
  });

  describe("useTheme hook", () => {
    it("should throw error when used outside ThemeProvider", () => {
      // Suppress console.error for this test
      const consoleSpy = jest.spyOn(console, "error").mockImplementation(() => {});
      
      expect(() => {
        render(<TestComponentWithoutProvider />);
      }).toThrow("useTheme must be used within a ThemeProvider");
      
      consoleSpy.mockRestore();
    });

    it("should provide theme value", () => {
      render(
        <ThemeProvider>
          <TestComponent />
        </ThemeProvider>
      );
      
      expect(screen.getByTestId("theme")).toHaveTextContent("light");
    });

    it("should toggle theme from light to dark", () => {
      render(
        <ThemeProvider>
          <TestComponent />
        </ThemeProvider>
      );
      
      expect(screen.getByTestId("theme")).toHaveTextContent("light");
      
      act(() => {
        screen.getByTestId("toggle").click();
      });
      
      expect(screen.getByTestId("theme")).toHaveTextContent("dark");
    });

    it("should toggle theme from dark to light", () => {
      localStorageMock.setItem("theme-preference", "dark");
      
      render(
        <ThemeProvider>
          <TestComponent />
        </ThemeProvider>
      );
      
      expect(screen.getByTestId("theme")).toHaveTextContent("dark");
      
      act(() => {
        screen.getByTestId("toggle").click();
      });
      
      expect(screen.getByTestId("theme")).toHaveTextContent("light");
    });

    it("should set theme to light explicitly", () => {
      localStorageMock.setItem("theme-preference", "dark");
      
      render(
        <ThemeProvider>
          <TestComponent />
        </ThemeProvider>
      );
      
      expect(screen.getByTestId("theme")).toHaveTextContent("dark");
      
      act(() => {
        screen.getByTestId("set-light").click();
      });
      
      expect(screen.getByTestId("theme")).toHaveTextContent("light");
    });

    it("should set theme to dark explicitly", () => {
      render(
        <ThemeProvider>
          <TestComponent />
        </ThemeProvider>
      );
      
      expect(screen.getByTestId("theme")).toHaveTextContent("light");
      
      act(() => {
        screen.getByTestId("set-dark").click();
      });
      
      expect(screen.getByTestId("theme")).toHaveTextContent("dark");
    });

    it("should persist theme to localStorage", () => {
      render(
        <ThemeProvider>
          <TestComponent />
        </ThemeProvider>
      );
      
      act(() => {
        screen.getByTestId("toggle").click();
      });
      
      expect(localStorageMock.setItem).toHaveBeenCalledWith("theme-preference", "dark");
    });

    it("should update document.documentElement class", () => {
      render(
        <ThemeProvider>
          <TestComponent />
        </ThemeProvider>
      );
      
      expect(document.documentElement.classList.contains("light")).toBe(true);
      
      act(() => {
        screen.getByTestId("toggle").click();
      });
      
      expect(document.documentElement.classList.contains("dark")).toBe(true);
      expect(document.documentElement.classList.contains("light")).toBe(false);
    });

    it("should remove previous theme class when changing", () => {
      render(
        <ThemeProvider>
          <TestComponent />
        </ThemeProvider>
      );
      
      // Add extra class to verify it's preserved
      document.documentElement.classList.add("extra-class");
      
      act(() => {
        screen.getByTestId("toggle").click();
      });
      
      expect(document.documentElement.classList.contains("dark")).toBe(true);
      expect(document.documentElement.classList.contains("light")).toBe(false);
      expect(document.documentElement.classList.contains("extra-class")).toBe(true);
    });

    it("should call onThemeChange callback when theme changes", () => {
      const onThemeChange = jest.fn();
      
      render(
        <ThemeProvider>
          <TestComponent onThemeChange={onThemeChange} />
        </ThemeProvider>
      );
      
      expect(onThemeChange).toHaveBeenCalledWith("light");
      
      act(() => {
        screen.getByTestId("toggle").click();
      });
      
      expect(onThemeChange).toHaveBeenCalledWith("dark");
    });

    it("should handle multiple rapid theme changes", () => {
      render(
        <ThemeProvider>
          <TestComponent />
        </ThemeProvider>
      );
      
      act(() => {
        screen.getByTestId("toggle").click();
        screen.getByTestId("toggle").click();
        screen.getByTestId("toggle").click();
      });
      
      // Should end up dark (odd number of toggles)
      expect(screen.getByTestId("theme")).toHaveTextContent("dark");
    });

    it("should maintain theme state across re-renders", () => {
      const { rerender } = render(
        <ThemeProvider>
          <TestComponent />
        </ThemeProvider>
      );
      
      act(() => {
        screen.getByTestId("toggle").click();
      });
      
      expect(screen.getByTestId("theme")).toHaveTextContent("dark");
      
      // Re-render the component
      rerender(
        <ThemeProvider>
          <TestComponent />
        </ThemeProvider>
      );
      
      expect(screen.getByTestId("theme")).toHaveTextContent("dark");
    });
  });

  describe("Edge cases", () => {
    it("should handle server-side rendering scenario", () => {
      // Simulate SSR by making window undefined temporarily
      const originalWindow = global.window;
      // @ts-ignore
      delete global.window;
      
      // This should not throw
      expect(() => {
        const { getStoredTheme, getSystemPreference } = require("@/contexts/ThemeContext");
        getStoredTheme();
        getSystemPreference();
      }).not.toThrow();
      
      // Restore window
      global.window = originalWindow;
    });

    it("should handle null localStorage value", () => {
      localStorageMock.getItem.mockReturnValue(null);
      
      render(
        <ThemeProvider>
          <TestComponent />
        </ThemeProvider>
      );
      
      expect(screen.getByTestId("theme")).toHaveTextContent("light");
    });

    it("should handle empty string localStorage value", () => {
      localStorageMock.getItem.mockReturnValue("");
      
      render(
        <ThemeProvider>
          <TestComponent />
        </ThemeProvider>
      );
      
      expect(screen.getByTestId("theme")).toHaveTextContent("light");
    });

    it("should handle undefined localStorage value", () => {
      localStorageMock.getItem.mockReturnValue(undefined as any);
      
      render(
        <ThemeProvider>
          <TestComponent />
        </ThemeProvider>
      );
      
      expect(screen.getByTestId("theme")).toHaveTextContent("light");
    });

    it("should work with multiple consumers", () => {
      const Consumer1: React.FC = () => {
        const { theme } = useTheme();
        return <span data-testid="consumer1">{theme}</span>;
      };
      
      const Consumer2: React.FC = () => {
        const { theme } = useTheme();
        return <span data-testid="consumer2">{theme}</span>;
      };
      
      render(
        <ThemeProvider>
          <Consumer1 />
          <Consumer2 />
        </ThemeProvider>
      );
      
      expect(screen.getByTestId("consumer1")).toHaveTextContent("light");
      expect(screen.getByTestId("consumer2")).toHaveTextContent("light");
    });

    it("should update all consumers when theme changes", () => {
      const Consumer1: React.FC = () => {
        const { theme, toggleTheme } = useTheme();
        return (
          <div>
            <span data-testid="consumer1">{theme}</span>
            <button data-testid="toggle-consumer1" onClick={toggleTheme}>Toggle</button>
          </div>
        );
      };
      
      const Consumer2: React.FC = () => {
        const { theme } = useTheme();
        return <span data-testid="consumer2">{theme}</span>;
      };
      
      render(
        <ThemeProvider>
          <Consumer1 />
          <Consumer2 />
        </ThemeProvider>
      );
      
      act(() => {
        screen.getByTestId("toggle-consumer1").click();
      });
      
      expect(screen.getByTestId("consumer1")).toHaveTextContent("dark");
      expect(screen.getByTestId("consumer2")).toHaveTextContent("dark");
    });
  });
});
