import React, { createContext, useContext, useEffect, useState } from 'react';
import { settingsApi } from '../services/settingsApi';

type Theme = 'light' | 'dark';

interface ThemeContextType {
  theme: Theme;
  setTheme: (theme: Theme) => void;
  toggleTheme: () => void;
  loading: boolean;
}

const ThemeContext = createContext<ThemeContextType | undefined>(undefined);

export const useTheme = () => {
  const context = useContext(ThemeContext);
  if (context === undefined) {
    throw new Error('useTheme must be used within a ThemeProvider');
  }
  return context;
};

interface ThemeProviderProps {
  children: React.ReactNode;
}

export const ThemeProvider: React.FC<ThemeProviderProps> = ({ children }) => {
  const [theme, setThemeState] = useState<Theme>('light');
  const [loading, setLoading] = useState(true);

  // Load theme from user preferences on mount
  useEffect(() => {
    const loadTheme = async () => {
      try {
        const preferences = await settingsApi.getPreferences();
        setThemeState(preferences.theme);
        applyThemeToDocument(preferences.theme);
      } catch (error) {
        console.error('Failed to load theme preference:', error);
        // Fall back to system preference or default
        const systemTheme = window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
        setThemeState(systemTheme);
        applyThemeToDocument(systemTheme);
      } finally {
        setLoading(false);
      }
    };

    loadTheme();
  }, []);

  // Apply theme to document
  const applyThemeToDocument = (newTheme: Theme) => {
    const root = window.document.documentElement;
    root.classList.remove('light', 'dark');
    root.classList.add(newTheme);
    
    // Also set data attribute for additional styling hooks
    root.setAttribute('data-theme', newTheme);
    
    // Update meta theme-color for mobile browsers
    const metaThemeColor = document.querySelector('meta[name="theme-color"]');
    if (metaThemeColor) {
      metaThemeColor.setAttribute('content', newTheme === 'dark' ? '#1f2937' : '#ffffff');
    }
  };

  const setTheme = async (newTheme: Theme) => {
    try {
      setThemeState(newTheme);
      applyThemeToDocument(newTheme);
      
      // Update user preferences
      await settingsApi.updatePreferences({ theme: newTheme });
    } catch (error) {
      console.error('Failed to update theme preference:', error);
      // Revert on error
      setThemeState(theme);
      applyThemeToDocument(theme);
    }
  };

  const toggleTheme = () => {
    setTheme(theme === 'light' ? 'dark' : 'light');
  };

  const value: ThemeContextType = {
    theme,
    setTheme,
    toggleTheme,
    loading
  };

  return (
    <ThemeContext.Provider value={value}>
      {children}
    </ThemeContext.Provider>
  );
};