// jest-dom adds custom jest matchers for asserting on DOM nodes.
// allows you to do things like:
// expect(element).toHaveTextContent(/react/i)
// learn more: https://github.com/testing-library/jest-dom
import '@testing-library/jest-dom';
import { TextEncoder, TextDecoder } from 'util';

// React Router 7 requires TextEncoder/TextDecoder
global.TextEncoder = TextEncoder;
global.TextDecoder = TextDecoder as typeof global.TextDecoder;

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
  const errorMessage = typeof args[0] === 'string' ? args[0] :
                       args[0]?.message ? String(args[0].message) : '';

  if (
    // React act() warnings
    errorMessage.includes('The current testing environment is not configured to support act') ||
    errorMessage.includes('You called act(async () => ...) without await') ||
    errorMessage.includes('You seem to have overlapping act() calls') ||
    errorMessage.includes('inside a test was not wrapped in act') ||
    // Redux warnings
    errorMessage.includes('No reducer provided for key') ||
    // jsdom navigation warnings (window.location.reload not implemented)
    errorMessage.includes('Not implemented: navigation')
  ) {
    return;
  }
  originalError(...args);
};
