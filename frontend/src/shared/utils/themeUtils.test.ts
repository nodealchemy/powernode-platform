import { 
  validateThemeClasses,
  testThemeToggle,
  getThemeTestResults,
  validateThemeConsistency,
  testFormTheming
} from './themeUtils';

describe('themeUtils', () => {
  beforeEach(() => {
    // Reset DOM state before each test
    document.documentElement.className = '';
    document.documentElement.removeAttribute('data-theme');
    
    // Clear any existing style elements
    const existingStyles = document.querySelectorAll('style[data-test]');
    existingStyles.forEach(style => style.remove());
  });

  afterEach(() => {
    // Clean up after each test
    document.documentElement.className = '';
    document.documentElement.removeAttribute('data-theme');
    
    const testElements = document.querySelectorAll('[data-test-theme]');
    testElements.forEach(el => el.remove());
  });

  describe('validateThemeClasses', () => {
    it('detects light theme correctly', () => {
      document.documentElement.classList.add('light');
      
      const result = validateThemeClasses();
      
      expect(result.theme).toBe('light');
    });

    it('detects dark theme correctly', () => {
      document.documentElement.classList.add('dark');
      
      const result = validateThemeClasses();
      
      expect(result.theme).toBe('dark');
    });

    it('defaults to light theme when no theme class is present', () => {
      const result = validateThemeClasses();
      
      expect(result.theme).toBe('light');
    });

    it('extracts CSS custom properties', () => {
      // Add test CSS custom properties
      const style = document.createElement('style');
      style.setAttribute('data-test', 'true');
      style.textContent = `
        :root {
          --color-background: #ffffff;
          --color-surface: #f8f9fa;
          --color-text-primary: #1a1a1a;
          --color-text-secondary: #6b7280;
          --color-border: #e5e7eb;
        }
      `;
      document.head.appendChild(style);
      
      const result = validateThemeClasses();
      
      expect(result.properties).toHaveProperty('--color-background');
      expect(result.properties).toHaveProperty('--color-surface');
      expect(result.properties).toHaveProperty('--color-text-primary');
      expect(result.properties).toHaveProperty('--color-text-secondary');
      expect(result.properties).toHaveProperty('--color-border');
      
      // Values should be strings (CSS property values)
      Object.values(result.properties).forEach(value => {
        expect(typeof value).toBe('string');
      });
    });

    it('handles missing CSS properties gracefully', () => {
      const result = validateThemeClasses();
      
      // Should still return properties object even if values are empty
      expect(result.properties).toBeInstanceOf(Object);
      expect(Object.keys(result.properties)).toHaveLength(5);
    });
  });

  describe('testThemeToggle', () => {
    it('toggles from light to dark theme', () => {
      document.documentElement.classList.add('light');
      
      const result = testThemeToggle();
      
      expect(document.documentElement.classList.contains('dark')).toBe(true);
      expect(document.documentElement.classList.contains('light')).toBe(false);
      expect(document.documentElement.getAttribute('data-theme')).toBe('dark');
      expect(result.theme).toBe('dark');
    });

    it('toggles from dark to light theme', () => {
      document.documentElement.classList.add('dark');
      
      const result = testThemeToggle();
      
      expect(document.documentElement.classList.contains('light')).toBe(true);
      expect(document.documentElement.classList.contains('dark')).toBe(false);
      expect(document.documentElement.getAttribute('data-theme')).toBe('light');
      expect(result.theme).toBe('light');
    });

    it('toggles from no theme class (default light) to dark', () => {
      // No theme class initially (defaults to light)
      const result = testThemeToggle();
      
      expect(document.documentElement.classList.contains('dark')).toBe(true);
      expect(document.documentElement.classList.contains('light')).toBe(false);
      expect(document.documentElement.getAttribute('data-theme')).toBe('dark');
      expect(result.theme).toBe('dark');
    });

    it('removes both theme classes before adding new one', () => {
      document.documentElement.classList.add('light', 'dark'); // Both present (invalid state)
      
      testThemeToggle();
      
      // Should only have one theme class
      const themeClasses = ['light', 'dark'].filter(cls => 
        document.documentElement.classList.contains(cls)
      );
      expect(themeClasses).toHaveLength(1);
    });

    it('updates data-theme attribute correctly', () => {
      document.documentElement.classList.add('light');
      document.documentElement.setAttribute('data-theme', 'light');
      
      testThemeToggle();
      
      expect(document.documentElement.getAttribute('data-theme')).toBe('dark');
      
      testThemeToggle();
      
      expect(document.documentElement.getAttribute('data-theme')).toBe('light');
    });
  });

  describe('getThemeTestResults', () => {
    it('performs complete theme toggle test cycle', () => {
      document.documentElement.classList.add('light');
      
      const results = getThemeTestResults();
      
      expect(results.initial.theme).toBe('light');
      expect(results.toggled.theme).toBe('dark');
      expect(results.final.theme).toBe('light');
      expect(results.success).toBe(true);
    });

    it('detects successful theme toggle cycle', () => {
      document.documentElement.classList.add('dark');
      
      const results = getThemeTestResults();
      
      expect(results.initial.theme).toBe('dark');
      expect(results.toggled.theme).toBe('light');
      expect(results.final.theme).toBe('dark');
      expect(results.success).toBe(true);
    });

    it('includes CSS properties in all states', () => {
      const results = getThemeTestResults();
      
      expect(results.initial.properties).toBeInstanceOf(Object);
      expect(results.toggled.properties).toBeInstanceOf(Object);
      expect(results.final.properties).toBeInstanceOf(Object);
    });
  });

  describe('validateThemeConsistency', () => {
    beforeEach(() => {
      // Clear any existing test elements
      const existingElements = document.querySelectorAll('[data-test-theme]');
      existingElements.forEach(el => el.remove());
    });

    it('identifies hardcoded gray colors', () => {
      // Add elements with hardcoded gray colors
      const div1 = document.createElement('div');
      div1.className = 'bg-gray-100 text-gray-600';
      div1.setAttribute('data-test-theme', 'true');
      document.body.appendChild(div1);

      const div2 = document.createElement('div');
      div2.className = 'border-gray-300';
      div2.setAttribute('data-test-theme', 'true');
      document.body.appendChild(div2);

      const result = validateThemeConsistency();

      expect(result.issues).toContain('Found 1 elements with hardcoded gray colors: [class*="bg-gray-"]');
      expect(result.issues).toContain('Found 1 elements with hardcoded gray colors: [class*="text-gray-"]');
      expect(result.issues).toContain('Found 1 elements with hardcoded gray colors: [class*="border-gray-"]');
      expect(result.consistent).toBe(false);
    });

    it('counts theme-aware elements correctly', () => {
      // Add elements with proper theme classes
      const elements = [
        { class: 'bg-theme-background', tag: 'div' },
        { class: 'bg-theme-surface', tag: 'section' },
        { class: 'text-theme-primary', tag: 'p' },
        { class: 'input-theme', tag: 'input' },
        { class: 'btn-theme-primary', tag: 'button' },
        { class: 'card-theme', tag: 'div' }
      ];

      elements.forEach(({ class: className, tag }) => {
        const el = document.createElement(tag);
        el.className = className;
        el.setAttribute('data-test-theme', 'true');
        document.body.appendChild(el);
      });

      const result = validateThemeConsistency();

      expect(result.themeElements['bg-theme-background']).toBe(1);
      expect(result.themeElements['bg-theme-surface']).toBe(1);
      expect(result.themeElements['text-theme-primary']).toBe(1);
      expect(result.themeElements['input-theme']).toBe(1);
      expect(result.themeElements['btn-theme']).toBe(1);
      expect(result.themeElements['card-theme']).toBe(1);
    });

    it('reports consistency when no hardcoded colors are found', () => {
      // Add only theme-aware elements
      const div = document.createElement('div');
      div.className = 'bg-theme-surface text-theme-primary border-theme';
      div.setAttribute('data-test-theme', 'true');
      document.body.appendChild(div);

      const result = validateThemeConsistency();

      expect(result.issues).toHaveLength(0);
      expect(result.consistent).toBe(true);
    });

    it('handles multiple hardcoded colors in single element', () => {
      const div = document.createElement('div');
      div.className = 'bg-gray-100 text-gray-600 border-gray-300';
      div.setAttribute('data-test-theme', 'true');
      document.body.appendChild(div);

      const result = validateThemeConsistency();

      // Should detect all three types of hardcoded colors
      const grayIssues = result.issues.filter(issue => issue.includes('hardcoded gray colors'));
      expect(grayIssues).toHaveLength(3);
    });

    it('ignores elements without hardcoded colors', () => {
      const div1 = document.createElement('div');
      div1.className = 'bg-blue-500 text-red-600'; // Non-gray hardcoded colors
      div1.setAttribute('data-test-theme', 'true');
      document.body.appendChild(div1);

      const div2 = document.createElement('div');
      div2.className = 'bg-theme-surface text-theme-primary';
      div2.setAttribute('data-test-theme', 'true');
      document.body.appendChild(div2);

      const result = validateThemeConsistency();

      // Should not find gray-specific hardcoded colors
      const grayIssues = result.issues.filter(issue => issue.includes('hardcoded gray colors'));
      expect(grayIssues).toHaveLength(0);
      expect(result.consistent).toBe(true);
    });
  });

  describe('testFormTheming', () => {
    beforeEach(() => {
      // Clear any existing test elements
      const existingElements = document.querySelectorAll('[data-test-theme]');
      existingElements.forEach(el => el.remove());
    });

    it('counts form elements correctly', () => {
      // Create test form elements
      const form = document.createElement('form');
      form.setAttribute('data-test-theme', 'true');
      document.body.appendChild(form);

      const input1 = document.createElement('input');
      input1.className = 'input-theme';
      input1.setAttribute('data-test-theme', 'true');
      document.body.appendChild(input1);

      const input2 = document.createElement('input');
      input2.className = 'input-theme';
      input2.setAttribute('data-test-theme', 'true');
      document.body.appendChild(input2);

      const button1 = document.createElement('button');
      button1.className = 'btn-theme-primary';
      button1.setAttribute('data-test-theme', 'true');
      document.body.appendChild(button1);

      const button2 = document.createElement('button');
      button2.className = 'btn-theme-secondary';
      button2.setAttribute('data-test-theme', 'true');
      document.body.appendChild(button2);

      const card = document.createElement('div');
      card.className = 'card-theme';
      card.setAttribute('data-test-theme', 'true');
      document.body.appendChild(card);

      const result = testFormTheming();

      expect(result.forms).toBe(1);
      expect(result.inputs).toBe(2);
      expect(result.buttons).toBe(2);
      expect(result.cards).toBe(1);
      expect(result.totalThemeElements).toBe(5); // inputs + buttons + cards
    });

    it('returns zero counts when no themed elements exist', () => {
      const result = testFormTheming();

      expect(result.forms).toBe(0);
      expect(result.inputs).toBe(0);
      expect(result.buttons).toBe(0);
      expect(result.cards).toBe(0);
      expect(result.totalThemeElements).toBe(0);
    });

    it('handles mixed themed and non-themed elements', () => {
      // Add themed elements
      const themedInput = document.createElement('input');
      themedInput.className = 'input-theme';
      themedInput.setAttribute('data-test-theme', 'true');
      document.body.appendChild(themedInput);

      const themedButton = document.createElement('button');
      themedButton.className = 'btn-theme-primary';
      themedButton.setAttribute('data-test-theme', 'true');
      document.body.appendChild(themedButton);

      // Add non-themed elements (should not be counted)
      const regularInput = document.createElement('input');
      regularInput.className = 'regular-input';
      regularInput.setAttribute('data-test-theme', 'true');
      document.body.appendChild(regularInput);

      const regularButton = document.createElement('button');
      regularButton.className = 'regular-button';
      regularButton.setAttribute('data-test-theme', 'true');
      document.body.appendChild(regularButton);

      const result = testFormTheming();

      expect(result.inputs).toBe(1); // Only themed input
      expect(result.buttons).toBe(1); // Only themed button
      expect(result.totalThemeElements).toBe(2);
    });

    it('counts different button theme variants', () => {
      const buttonClasses = [
        'btn-theme-primary',
        'btn-theme-secondary',
        'btn-theme-success',
        'btn-theme-danger',
        'btn-theme'
      ];

      buttonClasses.forEach(className => {
        const button = document.createElement('button');
        button.className = className;
        button.setAttribute('data-test-theme', 'true');
        document.body.appendChild(button);
      });

      const result = testFormTheming();

      expect(result.buttons).toBe(buttonClasses.length);
      expect(result.totalThemeElements).toBe(buttonClasses.length);
    });

    it('counts different card theme variants', () => {
      const cardClasses = [
        'card-theme',
        'card-theme-elevated',
        'card-theme-bordered'
      ];

      cardClasses.forEach(className => {
        const card = document.createElement('div');
        card.className = className;
        card.setAttribute('data-test-theme', 'true');
        document.body.appendChild(card);
      });

      const result = testFormTheming();

      expect(result.cards).toBe(cardClasses.length);
      expect(result.totalThemeElements).toBe(cardClasses.length);
    });
  });

  describe('integration scenarios', () => {
    it('validates complete theme implementation', () => {
      // Set up a complete themed page
      document.documentElement.classList.add('light');
      document.documentElement.setAttribute('data-theme', 'light');

      // Add CSS properties
      const style = document.createElement('style');
      style.setAttribute('data-test', 'true');
      style.textContent = `
        :root {
          --color-background: #ffffff;
          --color-surface: #f8f9fa;
          --color-text-primary: #1a1a1a;
          --color-text-secondary: #6b7280;
          --color-border: #e5e7eb;
        }
        :root.dark {
          --color-background: #1a1a1a;
          --color-surface: #2d2d2d;
          --color-text-primary: #ffffff;
          --color-text-secondary: #a1a1aa;
          --color-border: #404040;
        }
      `;
      document.head.appendChild(style);

      // Add properly themed elements
      const elements = [
        { tag: 'div', class: 'bg-theme-background' },
        { tag: 'section', class: 'bg-theme-surface' },
        { tag: 'p', class: 'text-theme-primary' },
        { tag: 'input', class: 'input-theme' },
        { tag: 'button', class: 'btn-theme-primary' },
        { tag: 'div', class: 'card-theme' },
        { tag: 'form', class: 'form-theme' }
      ];

      elements.forEach(({ tag, class: className }) => {
        const el = document.createElement(tag);
        el.className = className;
        el.setAttribute('data-test-theme', 'true');
        document.body.appendChild(el);
      });

      // Validate initial state
      const initialValidation = validateThemeClasses();
      expect(initialValidation.theme).toBe('light');

      // Test consistency
      const consistency = validateThemeConsistency();
      expect(consistency.consistent).toBe(true);
      expect(consistency.issues).toHaveLength(0);

      // Test form theming
      const formTheming = testFormTheming();
      expect(formTheming.totalThemeElements).toBeGreaterThan(0);

      // Test theme toggle functionality
      const toggleResults = getThemeTestResults();
      expect(toggleResults.success).toBe(true);
    });

    it('detects theme implementation issues', () => {
      // Add elements with hardcoded colors (bad practice)
      const elementsWithIssues = [
        { tag: 'div', class: 'bg-gray-100 text-gray-800' },
        { tag: 'button', class: 'bg-gray-500 border-gray-300' },
        { tag: 'input', class: 'border-gray-400' }
      ];

      elementsWithIssues.forEach(({ tag, class: className }) => {
        const el = document.createElement(tag);
        el.className = className;
        el.setAttribute('data-test-theme', 'true');
        document.body.appendChild(el);
      });

      const consistency = validateThemeConsistency();
      expect(consistency.consistent).toBe(false);
      expect(consistency.issues.length).toBeGreaterThan(0);
      
      // Should detect hardcoded gray colors
      const grayIssues = consistency.issues.filter(issue => 
        issue.includes('hardcoded gray colors')
      );
      expect(grayIssues.length).toBeGreaterThan(0);
    });

    it('handles mixed good and bad theme practices', () => {
      // Add good themed elements
      const goodElements = [
        { tag: 'div', class: 'bg-theme-surface text-theme-primary' },
        { tag: 'input', class: 'input-theme' },
        { tag: 'button', class: 'btn-theme-primary' }
      ];

      // Add problematic elements
      const badElements = [
        { tag: 'div', class: 'bg-gray-100' },
        { tag: 'span', class: 'text-gray-600' }
      ];

      [...goodElements, ...badElements].forEach(({ tag, class: className }) => {
        const el = document.createElement(tag);
        el.className = className;
        el.setAttribute('data-test-theme', 'true');
        document.body.appendChild(el);
      });

      const consistency = validateThemeConsistency();
      
      // Should detect issues but also count good elements
      expect(consistency.consistent).toBe(false);
      expect(consistency.issues.length).toBeGreaterThan(0);
      expect(consistency.themeElements['bg-theme-surface']).toBe(1);
      expect(consistency.themeElements['text-theme-primary']).toBe(1);
      expect(consistency.themeElements['input-theme']).toBe(1);
      expect(consistency.themeElements['btn-theme']).toBe(1);

      const formTheming = testFormTheming();
      expect(formTheming.inputs).toBe(1);
      expect(formTheming.buttons).toBe(1);
    });
  });

  describe('error handling', () => {
    it('handles DOM manipulation errors gracefully', () => {
      // Mock a scenario where classList operations might fail
      const originalClassList = document.documentElement.classList;
      
      // Create a mock classList that throws an error
      const mockClassList = {
        contains: jest.fn().mockImplementation(() => {
          throw new Error('DOM error');
        }),
        add: jest.fn(),
        remove: jest.fn()
      };

      Object.defineProperty(document.documentElement, 'classList', {
        value: mockClassList,
        configurable: true
      });

      // Should not throw an error
      expect(() => validateThemeClasses()).not.toThrow();

      // Restore original classList
      Object.defineProperty(document.documentElement, 'classList', {
        value: originalClassList,
        configurable: true
      });
    });

    it('handles missing CSS custom properties gracefully', () => {
      // Remove any existing style elements
      const styles = document.querySelectorAll('style');
      styles.forEach(style => style.remove());

      const result = validateThemeClasses();

      // Should return empty strings for missing properties but not crash
      expect(result.properties).toBeInstanceOf(Object);
      Object.values(result.properties).forEach(value => {
        expect(typeof value).toBe('string');
      });
    });

    it('handles querySelector errors gracefully', () => {
      // Mock querySelector to throw an error
      const originalQuerySelectorAll = document.querySelectorAll;
      document.querySelectorAll = jest.fn().mockImplementation(() => {
        throw new Error('Query error');
      });

      // Should not throw errors
      expect(() => validateThemeConsistency()).not.toThrow();
      expect(() => testFormTheming()).not.toThrow();

      // Restore original method
      document.querySelectorAll = originalQuerySelectorAll;
    });
  });
});