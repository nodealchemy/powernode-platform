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
    // Handle axios-style errors
    if ('response' in error && error.response && typeof error.response === 'object') {
      const response = error.response as any;
      if ('status' in response) statusCode = response.status;
      if ('data' in response && response.data && typeof response.data === 'object') {
        const responseData = response.data as any;
        errorMessage = responseData.error || responseData.message || errorMessage;
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
  // Tokens are now stored in Redux state (access_token) and HttpOnly cookies (refresh_token)
  // No localStorage cleanup needed for auth tokens
  // Impersonation tokens remain in localStorage and are cleared separately
};

/**
 * Checks if tokens exist in localStorage
 */
export const hasStoredTokens = (): boolean => {
  // Tokens are stored in Redux state and HttpOnly cookies, not localStorage
  // This function is kept for backward compatibility but always returns false
  return false;
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
    
    if (!payload.hasOwnProperty('exp') || payload.exp === null || payload.exp === undefined) return null;
    
    const expNumber = Number(payload.exp);
    if (isNaN(expNumber)) return null;
    
    return new Date(expNumber * 1000);
  } catch {
    return null;
  }
};