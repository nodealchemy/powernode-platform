import React, { createContext, useContext, useEffect, useState } from 'react';
import { useSelector } from 'react-redux';
import { RootState } from '@/shared/services';
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
  const [userTheme, setUserTheme] = useState<Theme>('light'); // Store user's preferred theme
  
  // Get authentication state with null checking
  const authState = useSelector((state: RootState) => state?.auth);
  const isAuthenticated = authState?.isAuthenticated || false;
  const hasValidTokens = authState?.accessToken && authState?.user;

  // Load theme from user preferences on mount (only if authenticated)
  useEffect(() => {
    const loadTheme = async () => {
      try {
        if (isAuthenticated && hasValidTokens) {
          const response = await settingsApi.getUserSettings();
          if (response.success) {
            const userTheme = response.data.user_preferences.theme || 'light';
            setUserTheme(userTheme);
            setThemeState(userTheme);
            applyThemeToDocument(userTheme);
          }
        } else {
          // Force light theme when logged out or tokens not available
          setThemeState('light');
          applyThemeToDocument('light');
        }
      } catch (error: any) {
        // Check if this is an authentication error
        if (error?.response?.status === 401) {
          // Authentication failed, use light theme
          setThemeState('light');
          applyThemeToDocument('light');
        } else if (isAuthenticated && hasValidTokens) {
          // Other error for authenticated user, fall back to system preference
          const systemTheme = window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
          setUserTheme(systemTheme);
          setThemeState(systemTheme);
          applyThemeToDocument(systemTheme);
        } else {
          // Always use light theme when not authenticated
          setThemeState('light');
          applyThemeToDocument('light');
        }
      } finally {
        setLoading(false);
      }
    };

    loadTheme();
  }, [isAuthenticated, hasValidTokens]);

  // Force light theme when user logs out or tokens become invalid
  useEffect(() => {
    if (!isAuthenticated || !hasValidTokens) {
      setThemeState('light');
      applyThemeToDocument('light');
    } else if (userTheme) {
      // Restore user's preferred theme when logging in with valid tokens
      setThemeState(userTheme);
      applyThemeToDocument(userTheme);
    }
  }, [isAuthenticated, hasValidTokens, userTheme]);

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
    // Prevent theme changes when logged out or tokens invalid
    if (!isAuthenticated || !hasValidTokens) {
      return;
    }

    try {
      setThemeState(newTheme);
      setUserTheme(newTheme);
      applyThemeToDocument(newTheme);
      
      // Update user preferences
      await settingsApi.updateUserSettings({ user_preferences: { theme: newTheme } });
    } catch (error: any) {
      // Check if authentication error
      if (error?.response?.status === 401) {
        // Authentication failed, keep the local theme change but don't try to save
        return;
      }
      // Revert on other errors
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