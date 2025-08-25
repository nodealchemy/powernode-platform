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
  parser: '@typescript-eslint/parser',
  parserOptions: {
    ecmaFeatures: {
      jsx: true
    },
    ecmaVersion: 'latest',
    sourceType: 'module'
  },
  rules: {
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

    // Code quality rules
    'no-console': 'warn',
    'no-debugger': 'warn',
    'no-unused-vars': 'off', // Handled by TypeScript
    '@typescript-eslint/no-unused-vars': ['warn', { argsIgnorePattern: '^_' }],
    'no-undef': 'off', // Handled by TypeScript
    
    // React-specific rules
    'react/jsx-uses-react': 'off', // Not needed in React 17+
    'react/react-in-jsx-scope': 'off', // Not needed in React 17+
    'react-hooks/exhaustive-deps': 'warn',
    
    // TypeScript rules
    '@typescript-eslint/no-explicit-any': 'warn',
    '@typescript-eslint/explicit-function-return-type': 'off',
    '@typescript-eslint/explicit-module-boundary-types': 'off',
    '@typescript-eslint/no-non-null-assertion': 'warn'
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
    // Test files
    {
      files: ['**/*.test.{js,ts,tsx}', '**/*.spec.{js,ts,tsx}', '**/cypress/**/*.{js,ts}'],
      rules: {
        'no-console': 'off',
        '@typescript-eslint/no-explicit-any': 'off',
        'security/detect-object-injection': 'off'
      }
    }
  ],
  settings: {
    react: {
      version: 'detect'
    }
  }
};