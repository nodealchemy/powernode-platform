import {
  isTokenInvalidError,
  clearStoredTokens,
  hasStoredTokens,
  isValidJWTFormat,
  getTokenExpiry
} from './tokenUtils';

// Mock localStorage
const localStorageMock = {
  getItem: jest.fn(),
  setItem: jest.fn(),
  removeItem: jest.fn(),
  clear: jest.fn()
};

Object.defineProperty(window, 'localStorage', {
  value: localStorageMock
});

describe('tokenUtils', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  // Helper function to create mock JWT tokens
  const createJWT = (payload: any) => {
    const header = btoa(JSON.stringify({ alg: 'HS256', typ: 'JWT' }));
    const payloadStr = btoa(JSON.stringify(payload));
    const signature = 'mock-signature';
    return `${header}.${payloadStr}.${signature}`;
  };

  describe('isTokenInvalidError', () => {
    it('returns false for falsy errors', () => {
      expect(isTokenInvalidError(null)).toBe(false);
      expect(isTokenInvalidError(undefined)).toBe(false);
      expect(isTokenInvalidError('')).toBe(false);
      expect(isTokenInvalidError(0)).toBe(false);
      expect(isTokenInvalidError(false)).toBe(false);
    });

    it('detects 401 status code errors', () => {
      const error401 = {
        response: {
          status: 401
        }
      };
      
      expect(isTokenInvalidError(error401)).toBe(true);
    });

    it('does not detect other HTTP status codes as token invalid', () => {
      const error400 = { response: { status: 400 } };
      const error403 = { response: { status: 403 } };
      const error404 = { response: { status: 404 } };
      const error500 = { response: { status: 500 } };
      
      expect(isTokenInvalidError(error400)).toBe(false);
      expect(isTokenInvalidError(error403)).toBe(false);
      expect(isTokenInvalidError(error404)).toBe(false);
      expect(isTokenInvalidError(error500)).toBe(false);
    });

    it('detects signature verification failed errors', () => {
      const signatureError = new Error('Signature verification failed');
      expect(isTokenInvalidError(signatureError)).toBe(true);
      
      const caseInsensitive = new Error('SIGNATURE VERIFICATION FAILED');
      expect(isTokenInvalidError(caseInsensitive)).toBe(true);
    });

    it('detects invalid token errors', () => {
      const invalidTokenError = new Error('Invalid token provided');
      expect(isTokenInvalidError(invalidTokenError)).toBe(true);
      
      const refreshTokenError = new Error('Invalid refresh token');
      expect(isTokenInvalidError(refreshTokenError)).toBe(true);
    });

    it('detects blacklisted token errors', () => {
      const blacklistedError = new Error('Token has been blacklisted');
      expect(isTokenInvalidError(blacklistedError)).toBe(true);
    });

    it('detects JWT decode errors', () => {
      const decodeError = new Error('JWT::DecodeError: Invalid token format');
      expect(isTokenInvalidError(decodeError)).toBe(true);
      
      const expiredError = new Error('JWT::ExpiredSignature: Token has expired');
      expect(isTokenInvalidError(expiredError)).toBe(true);
    });

    it('detects unauthorized errors', () => {
      const unauthorizedError = new Error('Unauthorized access');
      expect(isTokenInvalidError(unauthorizedError)).toBe(true);
      
      const accessTokenError = new Error('Invalid access token provided');
      expect(isTokenInvalidError(accessTokenError)).toBe(true);
    });

    it('extracts error messages from response data', () => {
      const apiError = {
        response: {
          status: 200, // Status is OK, but response contains error
          data: {
            error: 'Invalid token'
          }
        }
      };
      
      expect(isTokenInvalidError(apiError)).toBe(true);
      
      const messageError = {
        response: {
          data: {
            message: 'JWT::ExpiredSignature'
          }
        }
      };
      
      expect(isTokenInvalidError(messageError)).toBe(true);
    });

    it('handles nested response structures safely', () => {
      const malformedError = {
        response: null
      };
      
      expect(isTokenInvalidError(malformedError)).toBe(false);
      
      const emptyDataError = {
        response: {
          status: 401,
          data: null
        }
      };
      
      expect(isTokenInvalidError(emptyDataError)).toBe(true); // 401 status detected
    });

    it('is case insensitive for error patterns', () => {
      const upperCaseError = new Error('SIGNATURE VERIFICATION FAILED');
      const lowerCaseError = new Error('signature verification failed');
      const mixedCaseError = new Error('Signature Verification Failed');
      
      expect(isTokenInvalidError(upperCaseError)).toBe(true);
      expect(isTokenInvalidError(lowerCaseError)).toBe(true);
      expect(isTokenInvalidError(mixedCaseError)).toBe(true);
    });

    it('does not detect non-token-related errors', () => {
      const networkError = new Error('Network connection failed');
      const validationError = new Error('Validation failed for user input');
      const serverError = new Error('Internal server error');
      const notFoundError = new Error('Resource not found');
      
      expect(isTokenInvalidError(networkError)).toBe(false);
      expect(isTokenInvalidError(validationError)).toBe(false);
      expect(isTokenInvalidError(serverError)).toBe(false);
      expect(isTokenInvalidError(notFoundError)).toBe(false);
    });

    it('handles string errors correctly', () => {
      const stringError = 'Invalid token';
      expect(isTokenInvalidError(stringError)).toBe(true);
      
      const nonTokenString = 'Some other error';
      expect(isTokenInvalidError(nonTokenString)).toBe(false);
    });

    it('handles complex axios-style errors', () => {
      const axiosError = {
        name: 'AxiosError',
        message: 'Request failed with status code 401',
        response: {
          status: 401,
          statusText: 'Unauthorized',
          data: {
            error: 'JWT::ExpiredSignature',
            message: 'Token has expired'
          }
        }
      };
      
      expect(isTokenInvalidError(axiosError)).toBe(true);
    });

    it('prioritizes response data over main error message', () => {
      const errorWithResponseData = {
        message: 'Generic network error',
        response: {
          data: {
            error: 'Invalid refresh token'
          }
        }
      };
      
      expect(isTokenInvalidError(errorWithResponseData)).toBe(true);
    });
  });

  describe('clearStoredTokens', () => {
    it('removes both access and refresh tokens from localStorage', () => {
      clearStoredTokens();

      expect(localStorageMock.removeItem).toHaveBeenCalledWith('access_token');
      expect(localStorageMock.removeItem).toHaveBeenCalledWith('refresh_token');
      expect(localStorageMock.removeItem).toHaveBeenCalledTimes(2);
    });

    it('does not throw if localStorage operations fail', () => {
      localStorageMock.removeItem.mockImplementation(() => {
        throw new Error('Storage error');
      });
      
      expect(() => clearStoredTokens()).not.toThrow();
    });
  });

  describe('hasStoredTokens', () => {
    it('returns true when access token exists', () => {
      localStorageMock.getItem.mockImplementation((key) => {
        if (key === 'access_token') return 'access-token-value';
        return null;
      });

      expect(hasStoredTokens()).toBe(true);
    });

    it('returns true when refresh token exists', () => {
      localStorageMock.getItem.mockImplementation((key) => {
        if (key === 'refresh_token') return 'refresh-token-value';
        return null;
      });

      expect(hasStoredTokens()).toBe(true);
    });

    it('returns true when both tokens exist', () => {
      localStorageMock.getItem.mockImplementation((key) => {
        if (key === 'access_token') return 'access-token-value';
        if (key === 'refresh_token') return 'refresh-token-value';
        return null;
      });

      expect(hasStoredTokens()).toBe(true);
    });

    it('returns false when no tokens exist', () => {
      localStorageMock.getItem.mockReturnValue(null);
      
      expect(hasStoredTokens()).toBe(false);
    });

    it('returns false when tokens are empty strings', () => {
      localStorageMock.getItem.mockReturnValue('');
      
      expect(hasStoredTokens()).toBe(false);
    });

    it('handles localStorage errors gracefully', () => {
      localStorageMock.getItem.mockImplementation(() => {
        throw new Error('Storage not available');
      });
      
      expect(hasStoredTokens()).toBe(false);
    });
  });

  describe('isValidJWTFormat', () => {
    it('returns false for empty or null tokens', () => {
      expect(isValidJWTFormat('')).toBe(false);
      expect(isValidJWTFormat(null as any)).toBe(false);
      expect(isValidJWTFormat(undefined as any)).toBe(false);
    });

    it('returns true for properly formatted JWT tokens', () => {
      const validJWT = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c';
      expect(isValidJWTFormat(validJWT)).toBe(true);
    });

    it('returns false for tokens with wrong number of parts', () => {
      expect(isValidJWTFormat('header.payload')).toBe(false); // Only 2 parts
      expect(isValidJWTFormat('header.payload.signature.extra')).toBe(false); // 4 parts
      expect(isValidJWTFormat('header')).toBe(false); // Only 1 part
      expect(isValidJWTFormat('header.payload.signature.extra.more')).toBe(false); // Too many parts
    });

    it('returns true for tokens with empty parts (valid structure)', () => {
      expect(isValidJWTFormat('..')).toBe(true); // Three empty parts
      expect(isValidJWTFormat('header..')).toBe(true);
      expect(isValidJWTFormat('.payload.')).toBe(true);
      expect(isValidJWTFormat('..signature')).toBe(true);
    });

    it('handles tokens with invalid base64 content', () => {
      // Structure is valid, content might be invalid
      expect(isValidJWTFormat('invalid.base64.content')).toBe(true);
      expect(isValidJWTFormat('header@#$.payload&*(.signature!@#')).toBe(true);
    });
  });

  describe('getTokenExpiry', () => {
    it('returns null for invalid token format', () => {
      expect(getTokenExpiry('')).toBe(null);
      expect(getTokenExpiry('invalid')).toBe(null);
      expect(getTokenExpiry('header.payload')).toBe(null);
    });

    it('returns correct expiry date for valid token', () => {
      const expTimestamp = Math.floor(Date.now() / 1000) + 3600; // 1 hour from now
      const token = createJWT({ exp: expTimestamp });
      
      const expiry = getTokenExpiry(token);
      expect(expiry).toBeInstanceOf(Date);
      expect(expiry?.getTime()).toBe(expTimestamp * 1000);
    });

    it('returns null for token without exp claim', () => {
      const token = createJWT({ sub: '1234567890', name: 'John Doe' });
      
      expect(getTokenExpiry(token)).toBe(null);
    });

    it('returns null for token with null exp claim', () => {
      const token = createJWT({ exp: null });
      
      expect(getTokenExpiry(token)).toBe(null);
    });

    it('returns null for token with undefined exp claim', () => {
      const token = createJWT({ exp: undefined });
      
      expect(getTokenExpiry(token)).toBe(null);
    });

    it('handles tokens with malformed JSON payload', () => {
      const header = btoa(JSON.stringify({ alg: 'HS256', typ: 'JWT' }));
      const invalidPayload = btoa('invalid json {');
      const signature = 'mock-signature';
      const token = `${header}.${invalidPayload}.${signature}`;
      
      expect(getTokenExpiry(token)).toBe(null);
    });

    it('handles tokens with non-base64 payload', () => {
      const token = 'header.invalid-base64.signature';
      
      expect(getTokenExpiry(token)).toBe(null);
    });

    it('correctly converts Unix timestamp to Date', () => {
      const testCases = [
        1640995200, // 2022-01-01 00:00:00 UTC
        1672531200, // 2023-01-01 00:00:00 UTC
        0, // 1970-01-01 00:00:00 UTC
        2147483647 // Maximum 32-bit signed integer
      ];
      
      testCases.forEach(timestamp => {
        const token = createJWT({ exp: timestamp });
        const expiry = getTokenExpiry(token);
        
        expect(expiry).toBeInstanceOf(Date);
        expect(expiry?.getTime()).toBe(timestamp * 1000);
      });
    });

    it('handles negative timestamps', () => {
      const token = createJWT({ exp: -1 });
      const expiry = getTokenExpiry(token);
      
      expect(expiry).toBeInstanceOf(Date);
      expect(expiry?.getTime()).toBe(-1000);
    });

    it('handles floating point exp values', () => {
      const token = createJWT({ exp: 1640995200.5 });
      const expiry = getTokenExpiry(token);
      
      expect(expiry).toBeInstanceOf(Date);
      expect(expiry?.getTime()).toBe(1640995200500);
    });

    it('handles string exp values that can be converted to numbers', () => {
      const token = createJWT({ exp: '1640995200' });
      const expiry = getTokenExpiry(token);
      
      expect(expiry).toBeInstanceOf(Date);
      expect(expiry?.getTime()).toBe(1640995200000);
    });

    it('returns null for non-numeric exp values', () => {
      const token = createJWT({ exp: 'invalid-timestamp' });
      
      expect(getTokenExpiry(token)).toBe(null);
    });

    it('handles edge case with empty payload object', () => {
      const token = createJWT({});
      
      expect(getTokenExpiry(token)).toBe(null);
    });
  });

  describe('integration scenarios', () => {
    it('correctly identifies expired tokens', () => {
      const expiredTimestamp = Math.floor(Date.now() / 1000) - 3600; // 1 hour ago
      const expiredJWT = `eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.${btoa(JSON.stringify({ exp: expiredTimestamp }))}.signature`;

      expect(isValidJWTFormat(expiredJWT)).toBe(true);

      const expiry = getTokenExpiry(expiredJWT);
      expect(expiry).toBeInstanceOf(Date);
      expect(expiry!.getTime() < Date.now()).toBe(true);
    });

    it('handles complete authentication error workflow', () => {
      // Use a fresh mock for this test to ensure isolation
      const mockGetItem = jest.fn((key) => {
        if (key === 'access_token') return 'expired-token';
        if (key === 'refresh_token') return 'expired-refresh';
        return null;
      });

      // Apply the new mock
      localStorageMock.getItem = mockGetItem;

      expect(hasStoredTokens()).toBe(true);

      // API error occurs
      const authError = {
        response: {
          status: 401,
          data: {
            error: 'JWT::ExpiredSignature'
          }
        }
      };

      expect(isTokenInvalidError(authError)).toBe(true);

      // Clear tokens after error
      clearStoredTokens();

      expect(localStorageMock.removeItem).toHaveBeenCalledWith('access_token');
      expect(localStorageMock.removeItem).toHaveBeenCalledWith('refresh_token');
    });

    it('handles token format validation and expiry checking', () => {
      const currentTime = Math.floor(Date.now() / 1000);
      const validToken = `eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.${btoa(JSON.stringify({ exp: currentTime + 3600 }))}.signature`;
      const invalidToken = 'invalid-token-format';
      
      // Valid token
      expect(isValidJWTFormat(validToken)).toBe(true);
      const expiry = getTokenExpiry(validToken);
      expect(expiry).toBeInstanceOf(Date);
      expect(expiry!.getTime()).toBe((currentTime + 3600) * 1000);
      
      // Invalid token
      expect(isValidJWTFormat(invalidToken)).toBe(false);
      expect(getTokenExpiry(invalidToken)).toBe(null);
    });

    it('handles various error formats from different sources', () => {
      const errorFormats = [
        new Error('Invalid token'),
        { response: { status: 401 } },
        { response: { data: { error: 'Signature verification failed' } } },
        'Unauthorized',
        new Error('JWT::DecodeError')
      ];
      
      errorFormats.forEach(error => {
        expect(isTokenInvalidError(error)).toBe(true);
      });
      
      const nonTokenErrors = [
        new Error('Network error'),
        { response: { status: 404 } },
        { response: { data: { error: 'Not found' } } },
        'Server error',
        { message: 'Validation failed' }
      ];
      
      nonTokenErrors.forEach(error => {
        expect(isTokenInvalidError(error)).toBe(false);
      });
    });
  });

  describe('edge cases and error handling', () => {
    it('handles localStorage being unavailable', () => {
      // Mock localStorage methods to throw errors
      localStorageMock.getItem.mockImplementation(() => {
        throw new Error('localStorage not available');
      });
      localStorageMock.removeItem.mockImplementation(() => {
        throw new Error('localStorage not available');
      });
      
      expect(() => hasStoredTokens()).not.toThrow();
      expect(hasStoredTokens()).toBe(false);
      
      expect(() => clearStoredTokens()).not.toThrow();
    });

    it('handles circular reference objects in errors', () => {
      const circularError: any = { message: 'Circular error' };
      circularError.self = circularError;
      
      expect(() => isTokenInvalidError(circularError)).not.toThrow();
    });

    it('handles very large JWT tokens', () => {
      const largePayload = { exp: Math.floor(Date.now() / 1000) + 3600, data: 'x'.repeat(10000) };
      const largeToken = `header.${btoa(JSON.stringify(largePayload))}.signature`;
      
      expect(isValidJWTFormat(largeToken)).toBe(true);
      expect(getTokenExpiry(largeToken)).toBeInstanceOf(Date);
    });

    it('handles tokens with special characters', () => {
      // Test with ASCII-safe special characters that btoa can handle
      const payload = { 
        exp: Math.floor(Date.now() / 1000) + 3600, 
        name: 'John Doe', 
        special: 'user@example.com',
        symbols: '!@#$%^&*()'
      };
      const token = createJWT(payload);
      
      expect(getTokenExpiry(token)).toBeInstanceOf(Date);
    });
  });
});