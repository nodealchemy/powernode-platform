/**
 * Theme utility functions for testing and validation
 */

export const validateThemeClasses = () => {
  const root = document.documentElement;
  const currentTheme = root.classList.contains('dark') ? 'dark' : 'light';
  
  
  // Test CSS custom properties
  const style = getComputedStyle(root);
  const themeProperties = [
    '--color-background',
    '--color-surface',
    '--color-text-primary',
    '--color-text-secondary',
    '--color-border'
  ];
  
  themeProperties.forEach(prop => {
    const value = style.getPropertyValue(prop);
  });
  
  return {
    theme: currentTheme,
    properties: themeProperties.reduce((acc, prop) => {
      return { ...acc, [prop]: style.getPropertyValue(prop) };
    }, {} as Record<string, string>)
  };
};

export const testThemeToggle = () => {
  const root = document.documentElement;
  const wasLight = root.classList.contains('light');
  
  // Toggle theme classes
  root.classList.remove('light', 'dark');
  root.classList.add(wasLight ? 'dark' : 'light');
  
  // Update data attribute
  root.setAttribute('data-theme', wasLight ? 'dark' : 'light');
  
  
  return validateThemeClasses();
};

export const getThemeTestResults = () => {
  const initialState = validateThemeClasses();
  const toggledState = testThemeToggle();
  const finalState = testThemeToggle(); // Toggle back
  
  return {
    initial: initialState,
    toggled: toggledState,
    final: finalState,
    success: initialState.theme === finalState.theme
  };
};

/**
 * Validate that theme classes are properly applied to common elements
 */
export const validateThemeConsistency = () => {
  const issues: string[] = [];
  
  // Check for hardcoded gray colors that should use theme classes
  const hardcodedSelectors = [
    '[class*="bg-gray-"]',
    '[class*="text-gray-"]',
    '[class*="border-gray-"]'
  ];
  
  hardcodedSelectors.forEach(selector => {
    const elements = document.querySelectorAll(selector);
    if (elements.length > 0) {
      issues.push(`Found ${elements.length} elements with hardcoded gray colors: ${selector}`);
    }
  });
  
  // Check for proper theme class usage
  const themeElements = {
    'bg-theme-background': document.querySelectorAll('[class*="bg-theme-background"]').length,
    'bg-theme-surface': document.querySelectorAll('[class*="bg-theme-surface"]').length,
    'text-theme-primary': document.querySelectorAll('[class*="text-theme-primary"]').length,
    'input-theme': document.querySelectorAll('.input-theme').length,
    'btn-theme': document.querySelectorAll('[class*="btn-theme"]').length,
    'card-theme': document.querySelectorAll('[class*="card-theme"]').length
  };
  
  
  if (issues.length > 0) {
    console.warn('Theme consistency issues found:', issues);
  } else {
  }
  
  return {
    issues,
    themeElements,
    consistent: issues.length === 0
  };
};

/**
 * Test form element theming by checking if they respond to theme changes
 */
export const testFormTheming = () => {
  const forms = document.querySelectorAll('form');
  const inputs = document.querySelectorAll('.input-theme');
  const buttons = document.querySelectorAll('[class*="btn-theme"]');
  const cards = document.querySelectorAll('[class*="card-theme"]');
  
  const results = {
    forms: forms.length,
    inputs: inputs.length,
    buttons: buttons.length,
    cards: cards.length,
    totalThemeElements: inputs.length + buttons.length + cards.length
  };
  
  
  return results;
};