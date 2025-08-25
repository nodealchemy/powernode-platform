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
    // Strict security rules for production
    'security/detect-object-injection': 'error',
    'security/detect-non-literal-regexp': 'error',
    'security/detect-possible-timing-attacks': 'error',
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

    // Production code quality rules
    'no-console': 'error', // No console logs in production
    'no-debugger': 'error', // No debugger statements
    'no-unused-vars': 'off',
    '@typescript-eslint/no-unused-vars': 'error',
    'no-undef': 'off',
    
    // React-specific rules
    'react/jsx-uses-react': 'off',
    'react/react-in-jsx-scope': 'off',
    'react-hooks/exhaustive-deps': 'error',
    
    // Strict TypeScript rules
    '@typescript-eslint/no-explicit-any': 'error',
    '@typescript-eslint/explicit-function-return-type': 'off',
    '@typescript-eslint/explicit-module-boundary-types': 'warn',
    '@typescript-eslint/no-non-null-assertion': 'error'
  },
  overrides: [
    // Even admin components get strict rules in production
    {
      files: ['**/admin/**/*.{ts,tsx}', '**/features/admin/**/*.{ts,tsx}'],
      rules: {
        // Still allow object injection in admin - but require explicit disable comments
        'security/detect-object-injection': 'warn'
      }
    },
    // Test files can be more relaxed
    {
      files: ['**/*.test.{js,ts,tsx}', '**/*.spec.{js,ts,tsx}', '**/cypress/**/*.{js,ts}'],
      rules: {
        'no-console': 'warn',
        '@typescript-eslint/no-explicit-any': 'warn',
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