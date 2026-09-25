/**
 * Token utility functions for handling authentication tokens
 */

import type { AxiosError } from 'axios';

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
      const response = (error as AxiosError).response;
      if (response && 'status' in response) statusCode = response.status;
      if (response && 'data' in response && response.data && typeof response.data === 'object') {
        const responseData = response.data as Record<string, unknown>;
        errorMessage = String(responseData.error || responseData.message || errorMessage);
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
