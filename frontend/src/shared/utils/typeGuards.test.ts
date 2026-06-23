import { getErrorMessage, isObject } from './typeGuards';

describe('getErrorMessage', () => {
  it('returns the message of an Error instance (incl. subclasses)', () => {
    expect(getErrorMessage(new Error('boom'))).toBe('boom');
    expect(getErrorMessage(new TypeError('bad type'))).toBe('bad type');
  });

  it('returns a string error as-is', () => {
    expect(getErrorMessage('oops')).toBe('oops');
  });

  it('returns a plain object\'s string message property', () => {
    expect(getErrorMessage({ message: 'fail' })).toBe('fail');
  });

  it('falls through to the default when message is not a string (narrowing order)', () => {
    expect(getErrorMessage({ message: 42 })).toBe('An unexpected error occurred');
    expect(getErrorMessage({ code: 'E_X' })).toBe('An unexpected error occurred');
  });

  it('returns the default for null/undefined/number/array', () => {
    expect(getErrorMessage(null)).toBe('An unexpected error occurred');
    expect(getErrorMessage(undefined)).toBe('An unexpected error occurred');
    expect(getErrorMessage(123)).toBe('An unexpected error occurred');
    expect(getErrorMessage(['a'])).toBe('An unexpected error occurred');
  });
});

describe('isObject', () => {
  it('is true for plain objects (and other non-array objects)', () => {
    expect(isObject({})).toBe(true);
    expect(isObject({ a: 1 })).toBe(true);
    expect(isObject(new Error('x'))).toBe(true);
  });

  it('is false for null, arrays, and primitives', () => {
    expect(isObject(null)).toBe(false);
    expect(isObject([])).toBe(false);
    expect(isObject([1, 2])).toBe(false);
    expect(isObject('str')).toBe(false);
    expect(isObject(42)).toBe(false);
    expect(isObject(undefined)).toBe(false);
  });
});
