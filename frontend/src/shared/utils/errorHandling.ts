// Error handling utilities for TypeScript strict mode

export interface ErrorWithMessage {
  message: string;
}

export interface ErrorWithResponse {
  response?: {
    data?: {
      message?: string;
      error?: string;
    };
  };
  message: string;
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
  if (isErrorWithMessage(error)) {
    return error.message;
  }
  
  if (isErrorWithResponse(error)) {
    return error.response?.data?.message || error.response?.data?.error || error.message || 'An error occurred';
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