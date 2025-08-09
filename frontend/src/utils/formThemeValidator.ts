/**
 * Form Theme Validation Utility
 * Validates that form elements are using consistent theme classes
 */

export interface FormThemeIssue {
  type: 'hardcoded-color' | 'missing-theme-class' | 'inconsistent-text';
  element: string;
  selector: string;
  expected: string;
  actual: string;
}

export const validateFormTheme = (): FormThemeIssue[] => {
  const issues: FormThemeIssue[] = [];

  // Check for hardcoded text colors that should use theme classes
  const hardcodedSelectors = [
    { selector: '[class*="text-gray-"]', expected: 'text-theme-*' },
    { selector: '[class*="text-red-"]', expected: 'text-theme-error or alert-theme-error' },
    { selector: '[class*="bg-gray-"]', expected: 'bg-theme-*' },
    { selector: '[class*="border-gray-"]', expected: 'border-theme' },
    { selector: 'input:not(.input-theme)', expected: 'input-theme class' },
    { selector: 'textarea:not(.textarea-theme)', expected: 'textarea-theme class' },
    { selector: 'select:not(.select-theme)', expected: 'select-theme class' }
  ];

  hardcodedSelectors.forEach(({ selector, expected }) => {
    const elements = document.querySelectorAll(selector);
    elements.forEach(el => {
      // Skip elements that are intentionally styled (like brand colors)
      const className = el.className;
      if (!className.includes('text-blue-') && !className.includes('bg-blue-')) {
        issues.push({
          type: 'hardcoded-color',
          element: el.tagName.toLowerCase(),
          selector,
          expected,
          actual: className
        });
      }
    });
  });

  return issues;
};

export const getFormThemeStatistics = () => {
  const stats = {
    totalInputs: document.querySelectorAll('input').length,
    themedInputs: document.querySelectorAll('.input-theme').length,
    totalTextareas: document.querySelectorAll('textarea').length,
    themedTextareas: document.querySelectorAll('.textarea-theme').length,
    totalSelects: document.querySelectorAll('select').length,
    themedSelects: document.querySelectorAll('.select-theme').length,
    totalButtons: document.querySelectorAll('button').length,
    themedButtons: document.querySelectorAll('[class*="btn-theme"]').length,
    totalLabels: document.querySelectorAll('label').length,
    themedLabels: document.querySelectorAll('.label-theme').length
  };

  const coverage = {
    inputs: stats.totalInputs ? (stats.themedInputs / stats.totalInputs * 100).toFixed(1) : '0',
    textareas: stats.totalTextareas ? (stats.themedTextareas / stats.totalTextareas * 100).toFixed(1) : '0',
    selects: stats.totalSelects ? (stats.themedSelects / stats.totalSelects * 100).toFixed(1) : '0',
    buttons: stats.totalButtons ? (stats.themedButtons / stats.totalButtons * 100).toFixed(1) : '0',
    labels: stats.totalLabels ? (stats.themedLabels / stats.totalLabels * 100).toFixed(1) : '0'
  };

  return { stats, coverage };
};

export const testDarkModeConsistency = () => {
  const root = document.documentElement;
  const isDark = root.classList.contains('dark');
  
  // Get computed styles for key theme elements
  const sampleInput = document.querySelector('.input-theme') as HTMLElement;
  const sampleLabel = document.querySelector('.label-theme') as HTMLElement;
  
  if (!sampleInput || !sampleLabel) {
    console.warn('No themed form elements found for testing');
    return null;
  }
  
  const inputStyles = getComputedStyle(sampleInput);
  const labelStyles = getComputedStyle(sampleLabel);
  
  return {
    currentTheme: isDark ? 'dark' : 'light',
    inputTextColor: inputStyles.color,
    inputBackgroundColor: inputStyles.backgroundColor,
    labelTextColor: labelStyles.color,
    inputBorderColor: inputStyles.borderColor,
    placeholderColor: inputStyles.getPropertyValue('--color-text-tertiary') || 'Not set'
  };
};

export const logFormThemeReport = () => {
  console.group('🎨 Form Theme Validation Report');
  
  const issues = validateFormTheme();
  const { stats, coverage } = getFormThemeStatistics();
  const darkModeTest = testDarkModeConsistency();
  
  console.log('📊 Form Element Statistics:', stats);
  console.log('📈 Theme Coverage:', coverage);
  
  if (darkModeTest) {
    console.log('🌙 Dark Mode Consistency Test:', darkModeTest);
  }
  
  if (issues.length > 0) {
    console.warn(`⚠️ Found ${issues.length} theme consistency issues:`, issues);
  } else {
    console.log('✅ All form elements are using consistent theme classes!');
  }
  
  console.groupEnd();
  
  return {
    issues,
    stats,
    coverage,
    darkModeTest,
    isConsistent: issues.length === 0
  };
};