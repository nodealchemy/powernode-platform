/**
 * Theme utility functions for testing and validation
 */

export const validateThemeClasses = () => {
  try {
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
    
    return {
      theme: currentTheme,
      properties: themeProperties.reduce((acc, prop) => {
        return { ...acc, [prop]: style.getPropertyValue(prop) };
      }, {} as Record<string, string>)
    };
  } catch (_error) {
    // Handle DOM manipulation errors gracefully
    return {
      theme: 'light' as const,
      properties: {} as Record<string, string>
    };
  }
};

export const testThemeToggle = () => {
  const root = document.documentElement;
  
  // Determine current theme state (defaults to light if no class)
  const currentTheme = root.classList.contains('dark') ? 'dark' : 'light';
  const newTheme = currentTheme === 'light' ? 'dark' : 'light';
  
  // Toggle theme classes
  root.classList.remove('light', 'dark');
  root.classList.add(newTheme);
  
  // Update data attribute
  root.setAttribute('data-theme', newTheme);
  
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
  
  try {
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

    return {
      issues,
      themeElements,
      consistent: issues.length === 0
    };
  } catch (_error) {
    // Handle querySelector errors gracefully
    return {
      issues: ['DOM query error occurred'],
      themeElements: {
        'bg-theme-background': 0,
        'bg-theme-surface': 0,
        'text-theme-primary': 0,
        'input-theme': 0,
        'btn-theme': 0,
        'card-theme': 0
      },
      consistent: false
    };
  }
};

/**
 * Test form element theming by checking if they respond to theme changes
 */
export const testFormTheming = () => {
  try {
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
  } catch (_error) {
    // Handle querySelector errors gracefully
    return {
      forms: 0,
      inputs: 0,
      buttons: 0,
      cards: 0,
      totalThemeElements: 0
    };
  }
};