// Error handling utilities for TypeScript strict mode

export interface ErrorWithMessage {
  message: string;
}

export interface ErrorWithResponse {
  response?: {
    data?: {
      message?: string;
      error?: string;
      errors?: string[];
    };
    status?: number;
  };
  message: string;
}

/**
 * Structured API error with status code and details
 */
export interface ApiErrorDetails {
  message: string;
  status?: number;
  errors?: string[];
  originalError?: unknown;
}

// Type guard to check if error has message property
export function isErrorWithMessage(error: unknown): error is ErrorWithMessage {
  return (
    typeof error === 'object' &&
    error !== null &&
    'message' in error &&
    typeof (error as Record<string, unknown>).message === 'string'
  );
}

// Type guard to check if error has response property
export function isErrorWithResponse(error: unknown): error is ErrorWithResponse {
  return (
    typeof error === 'object' &&
    error !== null &&
    'response' in error
  );
}

// Get error message from unknown error
export function getErrorMessage(error: unknown): string {
  // Check for response data first to prioritize API error messages
  if (isErrorWithResponse(error)) {
    const responseMessage = error.response?.data?.message || error.response?.data?.error;
    if (responseMessage) {
      return responseMessage;
    }
    // Fall back to main message if response data doesn't have message/error
    if (error.message) {
      return error.message;
    }
    return 'An error occurred';
  }
  
  if (isErrorWithMessage(error)) {
    return error.message;
  }

  if (typeof error === 'string') {
    return error;
  }

  return 'An unexpected error occurred';
}

// Create a formatted error object from unknown error
export function createErrorObject(error: unknown) {
  return {
    message: getErrorMessage(error),
    originalError: error
  };
}

// ErrorHandler class for compatibility with legacy code
export class ErrorHandler {
  static getUserMessage(error: unknown): string {
    return getErrorMessage(error);
  }

  static log(message: string | Error, context?: Record<string, unknown>): void {
    if (process.env.NODE_ENV === 'development') {
      if (typeof message === 'string') {
        console.error(message, context || {});
      } else {
        console.error(message.message, { error: message, ...context });
      }
    }
  }
}

// ============================================================
// API-Specific Error Handling
// ============================================================

/**
 * Extracts HTTP status code from error
 */
export function getErrorStatus(error: unknown): number | undefined {
  if (isErrorWithResponse(error)) {
    return error.response?.status;
  }
  return undefined;
}

/**
 * Extracts validation errors array from API error response
 */
export function getValidationErrors(error: unknown): string[] {
  if (isErrorWithResponse(error) && error.response?.data?.errors) {
    return error.response.data.errors;
  }
  return [];
}

/**
 * Creates a detailed API error object from unknown error
 */
export function createApiError(error: unknown): ApiErrorDetails {
  return {
    message: getErrorMessage(error),
    status: getErrorStatus(error),
    errors: getValidationErrors(error),
    originalError: error,
  };
}

/**
 * Checks if error is a network error (no response)
 */
export function isNetworkError(error: unknown): boolean {
  if (isErrorWithResponse(error)) {
    return error.response === undefined;
  }
  if (isErrorWithMessage(error)) {
    return error.message === 'Network Error' || error.message.includes('network');
  }
  return false;
}

/**
 * Checks if error is an authentication error (401)
 */
export function isAuthError(error: unknown): boolean {
  return getErrorStatus(error) === 401;
}

/**
 * Checks if error is a forbidden error (403)
 */
export function isForbiddenError(error: unknown): boolean {
  return getErrorStatus(error) === 403;
}

/**
 * Checks if error is a not found error (404)
 */
export function isNotFoundError(error: unknown): boolean {
  return getErrorStatus(error) === 404;
}

/**
 * Checks if error is a validation error (422)
 */
export function isValidationError(error: unknown): boolean {
  return getErrorStatus(error) === 422;
}

/**
 * Checks if error is a server error (5xx)
 */
export function isServerError(error: unknown): boolean {
  const status = getErrorStatus(error);
  return status !== undefined && status >= 500 && status < 600;
}

/**
 * Gets a user-friendly error message based on error type
 */
export function getUserFriendlyError(error: unknown): string {
  if (isNetworkError(error)) {
    return 'Unable to connect to the server. Please check your internet connection.';
  }
  if (isAuthError(error)) {
    return 'Your session has expired. Please log in again.';
  }
  if (isForbiddenError(error)) {
    return 'You do not have permission to perform this action.';
  }
  if (isNotFoundError(error)) {
    return 'The requested resource was not found.';
  }
  if (isValidationError(error)) {
    const errors = getValidationErrors(error);
    if (errors.length > 0) {
      return errors.join('. ');
    }
    return 'Please check your input and try again.';
  }
  if (isServerError(error)) {
    return 'A server error occurred. Please try again later.';
  }

  return getErrorMessage(error);
}