// jest-dom adds custom jest matchers for asserting on DOM nodes.
// allows you to do things like:
// expect(element).toHaveTextContent(/react/i)
// learn more: https://github.com/testing-library/jest-dom
import '@testing-library/jest-dom';

// Suppress testing-related console warnings that don't affect functionality
const originalError = console.error;
console.error = (...args: unknown[]) => {
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
