/**
 * Token utility functions for handling authentication tokens
 */

/**
 * Checks if an error indicates token invalidity that requires immediate clearing
 */
export const isTokenInvalidError = (error: unknown): boolean => {
  if (!error) return false;
  
  // Extract error message safely
  let errorMessage = String(error);
  let statusCode = 0;
  
  if (error instanceof Error) {
    errorMessage = error.message;
  } else if (error && typeof error === 'object') {
    // Handle axios-style errors with type-safe property access
    const errorObj = error as Record<string, unknown>;
    if ('response' in errorObj && errorObj.response && typeof errorObj.response === 'object') {
      const response = errorObj.response as Record<string, unknown>;
      if ('status' in response && typeof response.status === 'number') {
        statusCode = response.status;
      }
      if ('data' in response && response.data && typeof response.data === 'object') {
        const responseData = response.data as Record<string, unknown>;
        errorMessage = (typeof responseData.error === 'string' ? responseData.error : null) ||
                       (typeof responseData.message === 'string' ? responseData.message : null) ||
                       errorMessage;
      }
    }
  }
  
  // Detect token invalidity patterns
  const invalidTokenPatterns = [
    'invalid token',
    'invalid access token', 
    'invalid refresh token',
    'token invalid',
    'expired token',
    'unauthorized',
    'jwt',
    'decode',
    'signature',
    'blacklisted'
  ];
  
  // 401 status code is typically token-related
  const hasInvalidTokenPattern = invalidTokenPatterns.some(pattern => 
    errorMessage.toLowerCase().includes(pattern.toLowerCase())
  );
  
  return statusCode === 401 || hasInvalidTokenPattern;
};

/**
 * Clears all authentication tokens from localStorage
 */
export const clearStoredTokens = (): void => {
  try {
    localStorage.removeItem('access_token');
    localStorage.removeItem('refresh_token');
  } catch {
    // Silently handle localStorage errors (e.g., when storage is disabled)
    if (process.env.NODE_ENV === 'development') {
      console.warn('Failed to clear stored tokens:', error);
    }
  }
};

/**
 * Checks if tokens exist in localStorage
 */
export const hasStoredTokens = (): boolean => {
  try {
    return !!(localStorage.getItem('access_token') || localStorage.getItem('refresh_token'));
  } catch {
    // Handle localStorage errors gracefully
    return false;
  }
};

/**
 * Validates token format - this app uses JWT tokens after authentication conversion
 * JWT tokens have 3 parts separated by dots: header.payload.signature
 */
export const isValidTokenFormat = (token: string): boolean => {
  if (!token || typeof token !== 'string') return false;
  
  // JWT tokens should have exactly 3 parts separated by dots
  return isValidJWTFormat(token);
};

/**
 * Checks if a token has JWT format (3 parts separated by dots)
 * Maintains backward compatibility for testing JWT scenarios
 */
export const isValidJWTFormat = (token: string): boolean => {
  if (!token || typeof token !== 'string') return false;
  
  // Check if it looks like a JWT (3 parts separated by dots)
  const parts = token.split('.');
  return parts.length === 3; // Allow empty parts for structural validity
};

/**
 * Gets token expiration time for JWT tokens (for testing/legacy support)
 */
export const getTokenExpiry = (token: string): Date | null => {
  try {
    // Only work with actual JWT format tokens
    if (!isValidJWTFormat(token)) return null;
    
    const parts = token.split('.');
    const payload = JSON.parse(atob(parts[1]));
    
    if (!Object.hasOwn(payload, 'exp') || payload.exp === null || payload.exp === undefined) return null;
    
    const expNumber = Number(payload.exp);
    if (isNaN(expNumber)) return null;
    
    return new Date(expNumber * 1000);
  } catch {
    return null;
  }
};