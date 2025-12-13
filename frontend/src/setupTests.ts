// jest-dom adds custom jest matchers for asserting on DOM nodes.
// allows you to do things like:
// expect(element).toHaveTextContent(/react/i)
// learn more: https://github.com/testing-library/jest-dom
import '@testing-library/jest-dom';

// Mock import.meta for Jest compatibility with Vite
Object.defineProperty(globalThis, 'import', {
  value: {
    meta: {
      env: {
        VITE_API_BASE_URL: 'http://localhost:3000/api/v1',
        VITE_AUTO_DETECT_BACKEND: 'false',
        VITE_BEHIND_PROXY: 'false'
      }
    }
  }
});

// Suppress testing-related console warnings that don't affect functionality
// eslint-disable-next-line no-console
const originalError = console.error;
// eslint-disable-next-line no-console
console.error = (...args: any[]) => {
  if (
    typeof args[0] === 'string' &&
    (args[0].includes('The current testing environment is not configured to support act') ||
     args[0].includes('You called act(async () => ...) without await') ||
     args[0].includes('You seem to have overlapping act() calls') ||
     args[0].includes('No reducer provided for key'))
  ) {
    return;
  }
  originalError(...args);
};
