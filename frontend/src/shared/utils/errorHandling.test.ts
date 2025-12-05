import {
  isErrorWithMessage,
  isErrorWithResponse,
  getErrorMessage,
  createErrorObject
} from './errorHandling';

describe('errorHandling utilities', () => {
  describe('isErrorWithMessage', () => {
    it('returns true for objects with message property', () => {
      const error = { message: 'Test error' };
      expect(isErrorWithMessage(error)).toBe(true);
    });

    it('returns true for Error instances', () => {
      const error = new Error('Test error');
      expect(isErrorWithMessage(error)).toBe(true);
    });

    it('returns false for null', () => {
      expect(isErrorWithMessage(null)).toBe(false);
    });

    it('returns false for undefined', () => {
      expect(isErrorWithMessage(undefined)).toBe(false);
    });

    it('returns false for objects without message property', () => {
      const error = { code: 500 };
      expect(isErrorWithMessage(error)).toBe(false);
    });

    it('returns false for objects with non-string message', () => {
      const error = { message: 123 };
      expect(isErrorWithMessage(error)).toBe(false);
    });

    it('returns false for primitive values', () => {
      expect(isErrorWithMessage('error string')).toBe(false);
      expect(isErrorWithMessage(123)).toBe(false);
      expect(isErrorWithMessage(true)).toBe(false);
    });
  });

  describe('isErrorWithResponse', () => {
    it('returns true for objects with response property', () => {
      const error = {
        message: 'API error',
        response: { data: { error: 'Server error' } }
      };
      expect(isErrorWithResponse(error)).toBe(true);
    });

    it('returns true for axios-style errors', () => {
      const error = {
        message: 'Request failed',
        response: {
          status: 500,
          data: { message: 'Internal server error' }
        }
      };
      expect(isErrorWithResponse(error)).toBe(true);
    });

    it('returns false for objects without response property', () => {
      const error = { message: 'Simple error' };
      expect(isErrorWithResponse(error)).toBe(false);
    });

    it('returns false for null and undefined', () => {
      expect(isErrorWithResponse(null)).toBe(false);
      expect(isErrorWithResponse(undefined)).toBe(false);
    });
  });

  describe('getErrorMessage', () => {
    it('extracts message from Error instances', () => {
      const error = new Error('Standard error message');
      expect(getErrorMessage(error)).toBe('Standard error message');
    });

    it('extracts message from objects with message property', () => {
      const error = { message: 'Custom error message' };
      expect(getErrorMessage(error)).toBe('Custom error message');
    });

    it('extracts message from response.data.message', () => {
      const error = {
        message: 'Request failed',
        response: {
          data: {
            message: 'Validation failed'
          }
        }
      };
      expect(getErrorMessage(error)).toBe('Validation failed');
    });

    it('extracts message from response.data.error', () => {
      const error = {
        message: 'Request failed',
        response: {
          data: {
            error: 'Authentication required'
          }
        }
      };
      expect(getErrorMessage(error)).toBe('Authentication required');
    });

    it('falls back to main message when response.data is empty', () => {
      const error = {
        message: 'Network error',
        response: {
          data: {}
        }
      };
      expect(getErrorMessage(error)).toBe('Network error');
    });

    it('falls back to "An error occurred" when response has no message', () => {
      const error = {
        message: '',
        response: {
          data: {}
        }
      };
      expect(getErrorMessage(error)).toBe('An error occurred');
    });

    it('handles string errors', () => {
      expect(getErrorMessage('String error message')).toBe('String error message');
    });

    it('handles null and undefined', () => {
      expect(getErrorMessage(null)).toBe('An unexpected error occurred');
      expect(getErrorMessage(undefined)).toBe('An unexpected error occurred');
    });

    it('handles unknown object types', () => {
      const error = { code: 500, details: 'Server error' };
      expect(getErrorMessage(error)).toBe('An unexpected error occurred');
    });

    it('handles complex nested response structures', () => {
      const error = {
        message: 'Request failed',
        response: {
          status: 422,
          data: {
            message: 'Validation failed',
            errors: {
              email: ['is required'],
              password: ['is too short']
            }
          }
        }
      };
      expect(getErrorMessage(error)).toBe('Validation failed');
    });

    it('handles response without data', () => {
      const error = {
        message: 'Connection timeout',
        response: {
          status: 408
        }
      };
      expect(getErrorMessage(error)).toBe('Connection timeout');
    });

    it('prioritizes response.data.message over response.data.error', () => {
      const error = {
        message: 'Request failed',
        response: {
          data: {
            message: 'Priority message',
            error: 'Secondary error'
          }
        }
      };
      expect(getErrorMessage(error)).toBe('Priority message');
    });

    it('handles empty string messages appropriately', () => {
      const error = {
        message: '',
        response: {
          data: {
            message: ''
          }
        }
      };
      expect(getErrorMessage(error)).toBe('An error occurred');
    });
  });

  describe('createErrorObject', () => {
    it('creates error object with message and originalError', () => {
      const originalError = new Error('Original error');
      const errorObject = createErrorObject(originalError);

      expect(errorObject).toEqual({
        message: 'Original error',
        originalError
      });
    });

    it('handles API response errors', () => {
      const originalError = {
        message: 'API Error',
        response: {
          data: {
            message: 'Server validation error'
          }
        }
      };

      const errorObject = createErrorObject(originalError);

      expect(errorObject).toEqual({
        message: 'Server validation error',
        originalError
      });
    });

    it('handles string errors', () => {
      const errorObject = createErrorObject('Simple string error');

      expect(errorObject).toEqual({
        message: 'Simple string error',
        originalError: 'Simple string error'
      });
    });

    it('handles null/undefined errors', () => {
      const nullErrorObject = createErrorObject(null);
      const undefinedErrorObject = createErrorObject(undefined);

      expect(nullErrorObject).toEqual({
        message: 'An unexpected error occurred',
        originalError: null
      });

      expect(undefinedErrorObject).toEqual({
        message: 'An unexpected error occurred',
        originalError: undefined
      });
    });

    it('preserves original error for debugging', () => {
      const complexError = {
        name: 'CustomError',
        message: 'Complex error',
        stack: 'Error stack trace...',
        customProperty: 'custom value',
        response: {
          status: 400,
          data: { error: 'Bad request' }
        }
      };

      const errorObject = createErrorObject(complexError);

      expect(errorObject.message).toBe('Bad request');
      expect(errorObject.originalError).toBe(complexError);
      expect(errorObject.originalError).toHaveProperty('customProperty', 'custom value');
    });
  });

  describe('Type safety and edge cases', () => {
    it('handles circular reference objects safely', () => {
      interface CircularError {
        message: string;
        self?: CircularError;
      }
      const circularError: CircularError = { message: 'Circular error' };
      circularError.self = circularError;

      expect(() => getErrorMessage(circularError)).not.toThrow();
      expect(getErrorMessage(circularError)).toBe('Circular error');
    });

    it('handles objects with prototype pollution attempts', () => {
      const maliciousError = Object.create(null) as { message: string; constructor: string };
      maliciousError.message = 'Prototype pollution attempt';
      maliciousError.constructor = 'malicious';

      expect(() => getErrorMessage(maliciousError)).not.toThrow();
      expect(getErrorMessage(maliciousError)).toBe('Prototype pollution attempt');
    });

    it('handles non-enumerable properties', () => {
      const error = {};
      Object.defineProperty(error, 'message', {
        value: 'Non-enumerable message',
        enumerable: false,
        writable: false
      });

      expect(getErrorMessage(error)).toBe('Non-enumerable message');
    });

    it('type guards work correctly with TypeScript for ErrorWithMessage', () => {
      const unknownError: unknown = new Error('TypeScript test');

      const result = isErrorWithMessage(unknownError);
      expect(result).toBe(true);

      // After the guard, we can access message
      if (result) {
        expect(typeof (unknownError as { message: string }).message).toBe('string');
      }
    });

    it('type guards work correctly with TypeScript for ErrorWithResponse', () => {
      const apiError: unknown = {
        message: 'API Error',
        response: { data: { error: 'Server error' } }
      };

      const result = isErrorWithResponse(apiError);
      expect(result).toBe(true);

      // After the guard, we can access response
      if (result) {
        const typedError = apiError as { message: string; response: { data: unknown } };
        expect(typedError.response).toBeDefined();
        expect(typeof typedError.message).toBe('string');
      }
    });

    it('handles deeply nested response structures', () => {
      const deepError = {
        message: 'Request failed',
        response: {
          data: {
            errors: {
              nested: {
                deeply: {
                  message: 'Deep nested message'
                }
              }
            },
            message: 'Top level message'
          }
        }
      };

      // Should prioritize top-level response.data.message
      expect(getErrorMessage(deepError)).toBe('Top level message');
    });

    it('handles response.data with null values', () => {
      const errorWithNull = {
        message: 'Base message',
        response: {
          data: {
            message: null,
            error: null
          }
        }
      };

      expect(getErrorMessage(errorWithNull)).toBe('Base message');
    });
  });
});
