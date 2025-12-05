module.exports = {
  root: true,
  extends: [
    'react-app',
    'react-app/jest'
  ],
  plugins: ['security'],
  env: {
    browser: true,
    es2021: true,
    node: true,
    jest: true
  },
  globals: {
    // Browser dialog functions - explicitly allowed
    confirm: 'readonly',
    alert: 'readonly',
    prompt: 'readonly'
  },
  parser: '@typescript-eslint/parser',
  parserOptions: {
    ecmaFeatures: {
      jsx: true
    },
    ecmaVersion: 'latest',
    sourceType: 'module'
  },
  rules: {
    // Allow browser confirmation dialogs (confirm, alert, prompt are valid browser APIs)
    'no-restricted-globals': ['error', 'event', 'fdescribe'],

    // Security rules with smart overrides for admin components
    'security/detect-object-injection': 'off', // Disabled - too many false positives in React apps
    'security/detect-non-literal-regexp': 'warn',
    'security/detect-possible-timing-attacks': 'warn', 
    'security/detect-pseudoRandomBytes': 'error',
    'security/detect-buffer-noassert': 'error',
    'security/detect-child-process': 'error',
    'security/detect-disable-mustache-escape': 'error',
    'security/detect-eval-with-expression': 'error',
    'security/detect-new-buffer': 'error',
    'security/detect-no-csrf-before-method-override': 'error',
    'security/detect-unsafe-regex': 'error',

    // Standard security rules
    'no-eval': 'error',
    'no-implied-eval': 'error',
    'no-new-func': 'error',
    'no-script-url': 'error',

    // Code quality rules - allow console methods for legitimate error handling and debugging
    'no-console': ['warn', { allow: ['error', 'warn', 'info', 'group', 'groupEnd', 'trace'] }],
    'no-debugger': 'warn',
    'no-unused-vars': 'off', // Handled by TypeScript
    '@typescript-eslint/no-unused-vars': ['warn', { argsIgnorePattern: '^_' }],
    'no-undef': 'off', // Handled by TypeScript
    
    // React-specific rules
    'react/jsx-uses-react': 'off', // Not needed in React 17+
    'react/react-in-jsx-scope': 'off', // Not needed in React 17+
    // exhaustive-deps disabled - the codebase uses many intentional mount-only effects
    // that would require extensive refactoring. These patterns are safe when understood.
    'react-hooks/exhaustive-deps': 'off',
    
    // TypeScript rules
    // Note: no-explicit-any disabled due to large existing codebase usage
    // Consider enabling per-file or per-directory as types are added
    '@typescript-eslint/no-explicit-any': 'off',
    '@typescript-eslint/explicit-function-return-type': 'off',
    '@typescript-eslint/explicit-module-boundary-types': 'off',
    '@typescript-eslint/no-non-null-assertion': 'off'
  },
  overrides: [
    // Relaxed rules for admin components (authenticated, permission-controlled)
    {
      files: ['**/admin/**/*.{ts,tsx}', '**/features/admin/**/*.{ts,tsx}'],
      rules: {
        'security/detect-object-injection': 'off', // Safe in authenticated admin contexts
        'security/detect-possible-timing-attacks': 'off' // Admin operations are authenticated
      }
    },
    // Relaxed rules for standardized UI components
    {
      files: ['**/shared/components/ui/**/*.{ts,tsx}'],
      rules: {
        'security/detect-object-injection': 'off' // Design system components use controlled prop access
      }
    },
    // Strict rules for public-facing components
    {
      files: ['**/public/**/*.{ts,tsx}', '**/pages/public/**/*.{ts,tsx}'],
      rules: {
        'security/detect-object-injection': 'error',
        'security/detect-possible-timing-attacks': 'error'
      }
    },
    // Test files - relax rules for testing flexibility
    {
      files: ['**/*.test.{js,ts,tsx}', '**/*.spec.{js,ts,tsx}', '**/cypress/**/*.{js,ts}', '**/__tests__/**/*.{js,ts,tsx}', '**/tests/**/*.{js,ts,tsx}'],
      rules: {
        'no-console': 'off',
        '@typescript-eslint/no-explicit-any': 'off',
        '@typescript-eslint/no-non-null-assertion': 'off',
        'security/detect-object-injection': 'off',
        // Testing Library rules - disabled for test flexibility
        'testing-library/no-unnecessary-act': 'off',
        'testing-library/no-wait-for-multiple-assertions': 'off',
        'testing-library/no-wait-for-side-effects': 'off',
        'testing-library/no-node-access': 'off',
        'testing-library/prefer-presence-queries': 'off',
        'testing-library/no-wait-for-empty-callback': 'off',
        'testing-library/no-container': 'off',
        // Jest rules - disabled for test flexibility
        'jest/no-conditional-expect': 'off'
      }
    }
  ],
  settings: {
    react: {
      version: 'detect'
    }
  }
};