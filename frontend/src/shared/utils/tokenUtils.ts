/**
 * Token utility functions for handling authentication tokens
 */

/**
 * Checks if an error indicates token invalidity that requires immediate clearing
 */
export const isTokenInvalidError = (error: any): boolean => {
  if (!error) return false;
  
  // Check for 401 status code first
  if (error.response?.status === 401) return true;
  
  const errorMessage = error.response?.data?.error || 
                      error.response?.data?.message || 
                      error.message || 
                      String(error);
  
  const invalidTokenPatterns = [
    'Signature verification failed',
    'Invalid token',
    'Invalid refresh token',
    'Token has been blacklisted',
    'JWT::DecodeError',
    'JWT::ExpiredSignature',
    'Unauthorized',
    'Invalid access token'
  ];
  
  return invalidTokenPatterns.some(pattern => 
    errorMessage.toLowerCase().includes(pattern.toLowerCase())
  );
};

/**
 * Clears all authentication tokens from localStorage
 */
export const clearStoredTokens = (): void => {
  localStorage.removeItem('accessToken');
  localStorage.removeItem('refreshToken');
};

/**
 * Checks if tokens exist in localStorage
 */
export const hasStoredTokens = (): boolean => {
  return !!(localStorage.getItem('accessToken') || localStorage.getItem('refreshToken'));
};

/**
 * Validates token format (basic JWT structure check)
 */
export const isValidJWTFormat = (token: string): boolean => {
  if (!token) return false;
  const parts = token.split('.');
  return parts.length === 3;
};

/**
 * Gets token expiration time without verification (for debugging)
 */
export const getTokenExpiry = (token: string): Date | null => {
  try {
    if (!isValidJWTFormat(token)) return null;
    
    const payload = JSON.parse(atob(token.split('.')[1]));
    if (!payload.exp) return null;
    
    return new Date(payload.exp * 1000);
  } catch {
    return null;
  }
};