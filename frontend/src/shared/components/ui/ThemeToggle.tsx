import React from 'react';
import { useSelector } from 'react-redux';
import { RootState } from '@/shared/services';
import { useTheme } from '@/shared/hooks/ThemeContext';
import { Button } from './Button';
import { Moon, Sun } from 'lucide-react';

interface ThemeToggleProps {
  className?: string;
  showLabel?: boolean;
}

export const ThemeToggle: React.FC<ThemeToggleProps> = ({ 
  className = '', 
  showLabel = false 
}) => {
  const { theme, toggleTheme, loading } = useTheme();
  const { isAuthenticated } = useSelector((state: RootState) => state.auth);

  // Hide theme toggle when logged out (forced to light theme)
  if (!isAuthenticated) {
    return null;
  }

  if (loading) {
    return (
      <div className={`animate-pulse ${className}`}>
        <div className="w-8 h-8 bg-theme-surface-disabled rounded-full"></div>
      </div>
    );
  }

  return (
    <Button
      onClick={toggleTheme}
      variant="ghost"
      size="sm"
      iconOnly={!showLabel}
      className={`rounded-full ${className}`}
      title={`Switch to ${theme === 'light' ? 'dark' : 'light'} theme`}
      aria-label={`Switch to ${theme === 'light' ? 'dark' : 'light'} theme`}
    >
      <div className="flex items-center">
        {theme === 'light' ? (
          <Moon className="w-4 h-4" />
        ) : (
          <Sun className="w-4 h-4" />
        )}
        {showLabel && (
          <span className="ml-2">
            {theme === 'light' ? 'Dark' : 'Light'}
          </span>
        )}
      </div>
    </Button>
  );
};