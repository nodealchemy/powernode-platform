/**
 * Token utility functions for handling authentication tokens
 */

/**
 * Checks if an error indicates token invalidity that requires immediate clearing
 */
export const isTokenInvalidError = (error: unknown): boolean => {
  if (!error) return false;
  
  // Check for 401 status code first
  if (error && typeof error === 'object' && 'response' in error && 
      error.response && typeof error.response === 'object' && 'status' in error.response &&
      (error.response as any).status === 401) {
    return true;
  }
  
  // Extract error message safely
  let errorMessage = String(error);
  if (error instanceof Error) {
    errorMessage = error.message;
  } else if (error && typeof error === 'object' && 'response' in error && 
             error.response && typeof error.response === 'object' && 'data' in error.response &&
             error.response.data && typeof error.response.data === 'object') {
    const responseData = error.response.data as any;
    errorMessage = responseData.error || responseData.message || errorMessage;
  }
  
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