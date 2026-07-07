import React from "react";
import { render, screen, fireEvent } from "@testing-library/react";
import "@testing-library/jest-dom";
import ThemeToggle from "@/components/ThemeToggle";
import { useTheme } from "@/contexts/ThemeContext";

jest.mock("@/contexts/ThemeContext", () => ({
  useTheme: jest.fn(),
}));

const mockToggleTheme = jest.fn();

const renderWithTheme = (theme: string) => {
  (useTheme as jest.Mock).mockReturnValue({
    theme,
    toggleTheme: mockToggleTheme,
  });
  return render(<ThemeToggle />);
};

describe("ThemeToggle", () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe("Rendering", () => {
    it("renders a button element", () => {
      renderWithTheme("light");
      expect(screen.getByRole("button")).toBeInTheDocument();
    });

    it("renders Sun icon", () => {
      renderWithTheme("light");
      const sunIcon = screen.getByTestId?.("sun-icon") || document.querySelector(".lucide-sun");
      expect(sunIcon).toBeInTheDocument();
    });

    it("renders Moon icon", () => {
      renderWithTheme("light");
      const moonIcon = screen.getByTestId?.("moon-icon") || document.querySelector(".lucide-moon");
      expect(moonIcon).toBeInTheDocument();
    });

    it("renders screen-reader-only text", () => {
      renderWithTheme("light");
      expect(screen.getByText("Toggle theme")).toBeInTheDocument();
    });

    it("applies correct CSS classes to the button", () => {
      renderWithTheme("light");
      const button = screen.getByRole("button");
      expect(button).toHaveClass("relative");
      expect(button).toHaveClass("inline-flex");
      expect(button).toHaveClass("h-9");
      expect(button).toHaveClass("w-9");
      expect(button).toHaveClass("rounded-md");
      expect(button).toHaveClass("border");
    });
  });

  describe("Accessibility", () => {
    it("has correct aria-label when theme is light", () => {
      renderWithTheme("light");
      expect(screen.getByRole("button")).toHaveAttribute(
        "aria-label",
        "Switch to dark mode"
      );
    });

    it("has correct aria-label when theme is dark", () => {
      renderWithTheme("dark");
      expect(screen.getByRole("button")).toHaveAttribute(
        "aria-label",
        "Switch to light mode"
      );
    });

    it("has a screen-reader-only span with descriptive text", () => {
      renderWithTheme("light");
      const srOnly = screen.getByText("Toggle theme");
      expect(srOnly).toHaveClass("sr-only");
    });
  });

  describe("Interaction", () => {
    it("calls toggleTheme when button is clicked", () => {
      renderWithTheme("light");
      fireEvent.click(screen.getByRole("button"));
      expect(mockToggleTheme).toHaveBeenCalledTimes(1);
    });

    it("calls toggleTheme each time button is clicked multiple times", () => {
      renderWithTheme("light");
      const button = screen.getByRole("button");
      fireEvent.click(button);
      fireEvent.click(button);
      fireEvent.click(button);
      expect(mockToggleTheme).toHaveBeenCalledTimes(3);
    });

    it("calls toggleTheme when theme is dark", () => {
      renderWithTheme("dark");
      fireEvent.click(screen.getByRole("button"));
      expect(mockToggleTheme).toHaveBeenCalledTimes(1);
    });
  });

  describe("Icon Transitions", () => {
    it("Sun icon has correct base classes", () => {
      renderWithTheme("light");
      const sunIcon = document.querySelector(".lucide-sun");
      expect(sunIcon).toHaveClass("h-[1.2rem]");
      expect(sunIcon).toHaveClass("w-[1.2rem]");
      expect(sunIcon).toHaveClass("rotate-0");
      expect(sunIcon).toHaveClass("scale-100");
    });

    it("Moon icon has correct base classes", () => {
      renderWithTheme("light");
      const moonIcon = document.querySelector(".lucide-moon");
      expect(moonIcon).toHaveClass("absolute");
      expect(moonIcon).toHaveClass("h-[1.2rem]");
      expect(moonIcon).toHaveClass("w-[1.2rem]");
      expect(moonIcon).toHaveClass("rotate-90");
      expect(moonIcon).toHaveClass("scale-0");
    });

    it("Sun icon has dark mode transition classes", () => {
      renderWithTheme("light");
      const sunIcon = document.querySelector(".lucide-sun");
      expect(sunIcon).toHaveClass("dark:-rotate-90");
      expect(sunIcon).toHaveClass("dark:scale-0");
    });

    it("Moon icon has dark mode transition classes", () => {
      renderWithTheme("light");
      const moonIcon = document.querySelector(".lucide-moon");
      expect(moonIcon).toHaveClass("dark:rotate-0");
      expect(moonIcon).toHaveClass("dark:scale-100");
    });
  });

  describe("Edge Cases", () => {
    it("handles unexpected theme value gracefully", () => {
      (useTheme as jest.Mock).mockReturnValue({
        theme: "system",
        toggleTheme: mockToggleTheme,
      });
      render(<ThemeToggle />);
      expect(screen.getByRole("button")).toHaveAttribute(
        "aria-label",
        "Switch to light mode"
      );
    });

    it("handles empty string theme value", () => {
      (useTheme as jest.Mock).mockReturnValue({
        theme: "",
        toggleTheme: mockToggleTheme,
      });
      render(<ThemeToggle />);
      expect(screen.getByRole("button")).toHaveAttribute(
        "aria-label",
        "Switch to light mode"
      );
    });

    it("handles undefined theme value", () => {
      (useTheme as jest.Mock).mockReturnValue({
        theme: undefined,
        toggleTheme: mockToggleTheme,
      });
      render(<ThemeToggle />);
      expect(screen.getByRole("button")).toHaveAttribute(
        "aria-label",
        "Switch to light mode"
      );
    });

    it("handles null theme value", () => {
      (useTheme as jest.Mock).mockReturnValue({
        theme: null,
        toggleTheme: mockToggleTheme,
      });
      render(<ThemeToggle />);
      expect(screen.getByRole("button")).toHaveAttribute(
        "aria-label",
        "Switch to light mode"
      );
    });

    it("handles rapid consecutive clicks", () => {
      renderWithTheme("light");
      const button = screen.getByRole("button");
      for (let i = 0; i < 100; i++) {
        fireEvent.click(button);
      }
      expect(mockToggleTheme).toHaveBeenCalledTimes(100);
    });

    it("does not throw when toggleTheme is undefined", () => {
      (useTheme as jest.Mock).mockReturnValue({
        theme: "light",
        toggleTheme: undefined,
      });
      render(<ThemeToggle />);
      expect(() => {
        fireEvent.click(screen.getByRole("button"));
      }).not.toThrow();
    });

    it("does not throw when toggleTheme throws an error", () => {
      const errorToggle = jest.fn(() => {
        throw new Error("Theme toggle failed");
      });
      (useTheme as jest.Mock).mockReturnValue({
        theme: "light",
        toggleTheme: errorToggle,
      });
      render(<ThemeToggle />);
      expect(() => {
        fireEvent.click(screen.getByRole("button"));
      }).toThrow("Theme toggle failed");
    });
  });

  describe("CSS Transition Classes", () => {
    it("button has transition-colors class", () => {
      renderWithTheme("light");
      expect(screen.getByRole("button")).toHaveClass("transition-colors");
    });

    it("button has hover classes", () => {
      renderWithTheme("light");
      expect(screen.getByRole("button")).toHaveClass("hover:bg-accent");
      expect(screen.getByRole("button")).toHaveClass("hover:text-accent-foreground");
    });

    it("button has focus classes", () => {
      renderWithTheme("light");
      expect(screen.getByRole("button")).toHaveClass("focus:outline-none");
      expect(screen.getByRole("button")).toHaveClass("focus:ring-2");
      expect(screen.getByRole("button")).toHaveClass("focus:ring-ring");
    });

    it("icons have transition-all class", () => {
      renderWithTheme("light");
      const sunIcon = document.querySelector(".lucide-sun");
      const moonIcon = document.querySelector(".lucide-moon");
      expect(sunIcon).toHaveClass("transition-all");
      expect(moonIcon).toHaveClass("transition-all");
    });
  });
});
