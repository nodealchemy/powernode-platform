import js from '@eslint/js';
import tseslint from 'typescript-eslint';
import reactPlugin from 'eslint-plugin-react';
import reactHooksPlugin from 'eslint-plugin-react-hooks';
import securityPlugin from 'eslint-plugin-security';
import globals from 'globals';

export default tseslint.config(
  // Global ignores (replaces .eslintignore)
  {
    ignores: [
      'node_modules/',
      '/.pnp',
      '.pnp.js',
      '/build',
      '/dist',
      'coverage/',
      '.env',
      '.env.local',
      '.env.development.local',
      '.env.test.local',
      '.env.production.local',
      'npm-debug.log*',
      'yarn-debug.log*',
      'yarn-error.log*',
      'pids',
      '*.pid',
      '*.seed',
      '*.pid.lock',
      'src/react-app-env.d.ts',
      'cypress/videos/',
      'cypress/screenshots/',
      '.vscode/',
      '.idea/',
      '.DS_Store',
      'Thumbs.db',
      '*.tmp',
      '*.temp',
      '.cache/',
      'docs/examples/',
      'docs/snippets/',
      'public/',
      'craco.config.js',
      '**/*.d.ts',
      '!src/**/*.d.ts',
    ],
  },

  // Base ESLint recommended rules
  js.configs.recommended,

  // TypeScript recommended rules
  ...tseslint.configs.recommended,

  // Main configuration for all TypeScript/React files
  {
    files: ['**/*.{ts,tsx,js,jsx}'],
    plugins: {
      'react': reactPlugin,
      'react-hooks': reactHooksPlugin,
      'security': securityPlugin,
    },
    languageOptions: {
      ecmaVersion: 'latest',
      sourceType: 'module',
      globals: {
        ...globals.browser,
        ...globals.es2021,
        ...globals.node,
        ...globals.jest,
        // Browser dialog functions - explicitly allowed
        confirm: 'readonly',
        alert: 'readonly',
        prompt: 'readonly',
      },
      parserOptions: {
        ecmaFeatures: {
          jsx: true,
        },
      },
    },
    settings: {
      react: {
        version: 'detect',
      },
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
      'react-hooks/rules-of-hooks': 'error',

      // TypeScript rules
      // Note: no-explicit-any disabled due to large existing codebase usage
      // Consider enabling per-file or per-directory as types are added
      '@typescript-eslint/no-explicit-any': 'off',
      '@typescript-eslint/explicit-function-return-type': 'off',
      '@typescript-eslint/explicit-module-boundary-types': 'off',
      '@typescript-eslint/no-non-null-assertion': 'off',
    },
  },

  // Relaxed rules for admin components (authenticated, permission-controlled)
  {
    files: ['**/admin/**/*.{ts,tsx}', '**/features/admin/**/*.{ts,tsx}'],
    rules: {
      'security/detect-object-injection': 'off', // Safe in authenticated admin contexts
      'security/detect-possible-timing-attacks': 'off', // Admin operations are authenticated
    },
  },

  // Relaxed rules for standardized UI components
  {
    files: ['**/shared/components/ui/**/*.{ts,tsx}'],
    rules: {
      'security/detect-object-injection': 'off', // Design system components use controlled prop access
    },
  },

  // Strict rules for public-facing components
  {
    files: ['**/public/**/*.{ts,tsx}', '**/pages/public/**/*.{ts,tsx}'],
    rules: {
      'security/detect-object-injection': 'error',
      'security/detect-possible-timing-attacks': 'error',
    },
  },

  // Test files - relax rules for testing flexibility
  {
    files: [
      '**/*.test.{js,ts,tsx}',
      '**/*.spec.{js,ts,tsx}',
      '**/cypress/**/*.{js,ts}',
      '**/__tests__/**/*.{js,ts,tsx}',
      '**/tests/**/*.{js,ts,tsx}',
    ],
    rules: {
      'no-console': 'off',
      '@typescript-eslint/no-explicit-any': 'off',
      '@typescript-eslint/no-non-null-assertion': 'off',
      'security/detect-object-injection': 'off',
    },
  }
);
