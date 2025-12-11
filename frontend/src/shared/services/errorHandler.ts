/**
 * Error Handler Utility for AI Orchestration
 *
 * Provides standardized error handling, type discrimination, and user-friendly messages.
 * Used across AI services and components for consistent error management.
 *
 * Includes hooks for error tracking services (Sentry, etc.)
 */
import axios, { AxiosError } from 'axios';

// =============================================================================
// ERROR TRACKING TYPES AND CONFIGURATION
// =============================================================================

/**
 * Error tracking context for enriching error reports
 */
export interface ErrorTrackingContext {
  userId?: string;
  accountId?: string;
  sessionId?: string;
  url?: string;
  component?: string;
  action?: string;
  tags?: Record<string, string>;
  extra?: Record<string, unknown>;
}

/**
 * Error tracking handler type
 * Implement this interface to integrate with Sentry, Datadog, etc.
 */
export type ErrorTrackingHandler = (
  error: Error | ApiError,
  context?: ErrorTrackingContext
) => void;

/**
 * Global error tracking configuration
 */
let errorTrackingHandler: ErrorTrackingHandler | null = null;
let globalContext: ErrorTrackingContext = {};

/**
 * Configure error tracking handler (e.g., Sentry)
 *
 * @param handler - Error tracking handler function
 *
 * @example
 * ```typescript
 * import * as Sentry from '@sentry/react';
 *
 * configureErrorTracking((error, context) => {
 *   Sentry.captureException(error, {
 *     user: { id: context?.userId },
 *     tags: context?.tags,
 *     extra: context?.extra
 *   });
 * });
 * ```
 */
export function configureErrorTracking(handler: ErrorTrackingHandler): void {
  errorTrackingHandler = handler;
}

/**
 * Set global context for all error reports
 *
 * @param context - Global context to include in all error reports
 */
export function setErrorTrackingContext(context: ErrorTrackingContext): void {
  globalContext = { ...globalContext, ...context };
}

/**
 * Clear error tracking context (e.g., on logout)
 */
export function clearErrorTrackingContext(): void {
  globalContext = {};
}

/**
 * Track an error with the configured tracking service
 *
 * @param error - Error to track
 * @param context - Additional context for this specific error
 */
export function trackError(
  error: Error | ApiError | unknown,
  context?: ErrorTrackingContext
): void {
  if (!errorTrackingHandler) {
    return;
  }

  const mergedContext = { ...globalContext, ...context };

  // Add URL context if in browser
  if (typeof window !== 'undefined') {
    mergedContext.url = mergedContext.url || window.location.href;
  }

  try {
    if (error instanceof Error) {
      errorTrackingHandler(error, mergedContext);
    } else {
      // Convert ApiError or unknown to Error
      const apiError = handleApiError(error);
      const errorInstance = new Error(apiError.message);
      errorInstance.name = apiError.code;
      errorTrackingHandler(errorInstance, {
        ...mergedContext,
        extra: {
          ...mergedContext.extra,
          apiError: apiError
        }
      });
    }
  } catch (trackingError) {
    // Don't let tracking errors crash the app
    if (process.env.NODE_ENV === 'development') {
      console.error('[ErrorTracking] Failed to track error:', trackingError);
    }
  }
}

/**
 * Structured API error representation
 */
export interface ApiError {
  code: string;
  message: string;
  details?: Record<string, unknown>;
  recoverable: boolean;
  statusCode?: number;
}

/**
 * Error codes for categorizing errors
 */
export const ErrorCodes = {
  // HTTP status-based errors
  UNAUTHORIZED: 'UNAUTHORIZED',
  FORBIDDEN: 'FORBIDDEN',
  NOT_FOUND: 'NOT_FOUND',
  VALIDATION_ERROR: 'VALIDATION_ERROR',
  RATE_LIMITED: 'RATE_LIMITED',
  SERVICE_UNAVAILABLE: 'SERVICE_UNAVAILABLE',
  SERVER_ERROR: 'SERVER_ERROR',

  // Network errors
  NETWORK_ERROR: 'NETWORK_ERROR',
  TIMEOUT_ERROR: 'TIMEOUT_ERROR',

  // Generic errors
  UNKNOWN_ERROR: 'UNKNOWN_ERROR',
} as const;

/**
 * Transform any error into a structured ApiError
 *
 * @param error - Any error type (Axios error, standard Error, unknown)
 * @returns Structured ApiError with user-friendly message
 */
export function handleApiError(error: unknown): ApiError {
  // Handle Axios errors (most common for API calls)
  if (axios.isAxiosError(error)) {
    return handleAxiosError(error);
  }

  // Handle standard Error objects
  if (error instanceof Error) {
    return handleStandardError(error);
  }

  // Handle unknown error types
  return {
    code: ErrorCodes.UNKNOWN_ERROR,
    message: 'An unexpected error occurred.',
    recoverable: false,
  };
}

/**
 * Handle Axios-specific errors with status code discrimination
 */
function handleAxiosError(error: AxiosError<{ error?: string; message?: string; errors?: string[] }>): ApiError {
  const status = error.response?.status;
  const serverMessage =
    error.response?.data?.error ||
    error.response?.data?.message ||
    error.response?.data?.errors?.join(', ');

  // Handle specific HTTP status codes
  switch (status) {
    case 401:
      return {
        code: ErrorCodes.UNAUTHORIZED,
        message: 'Your session has expired. Please log in again.',
        recoverable: false,
        statusCode: 401,
      };

    case 403:
      return {
        code: ErrorCodes.FORBIDDEN,
        message: serverMessage || 'You do not have permission to perform this action.',
        recoverable: false,
        statusCode: 403,
      };

    case 404:
      return {
        code: ErrorCodes.NOT_FOUND,
        message: serverMessage || 'The requested resource was not found.',
        recoverable: false,
        statusCode: 404,
      };

    case 422:
      return {
        code: ErrorCodes.VALIDATION_ERROR,
        message: serverMessage || 'Please check your input and try again.',
        details: error.response?.data as Record<string, unknown>,
        recoverable: false,
        statusCode: 422,
      };

    case 429:
      return {
        code: ErrorCodes.RATE_LIMITED,
        message: 'Too many requests. Please wait and try again.',
        recoverable: true,
        statusCode: 429,
      };

    case 503:
      return {
        code: ErrorCodes.SERVICE_UNAVAILABLE,
        message: 'Service temporarily unavailable. Please try again later.',
        recoverable: true,
        statusCode: 503,
      };

    default:
      // Check for network errors (no response)
      if (!error.response) {
        if (error.code === 'ECONNABORTED' || error.message.includes('timeout')) {
          return {
            code: ErrorCodes.TIMEOUT_ERROR,
            message: 'The request timed out. Please try again.',
            recoverable: true,
          };
        }

        return {
          code: ErrorCodes.NETWORK_ERROR,
          message: 'Unable to connect to the server. Please check your connection.',
          recoverable: true,
        };
      }

      // Generic server error
      return {
        code: ErrorCodes.SERVER_ERROR,
        message: serverMessage || 'An unexpected error occurred. Please try again.',
        recoverable: true,
        statusCode: status || 500,
      };
  }
}

/**
 * Handle standard JavaScript Error objects
 */
function handleStandardError(error: Error): ApiError {
  const message = error.message.toLowerCase();

  // Check for network-related errors
  if (message.includes('network') || message.includes('fetch')) {
    return {
      code: ErrorCodes.NETWORK_ERROR,
      message: 'Unable to connect to the server. Please check your connection.',
      recoverable: true,
    };
  }

  // Check for timeout errors
  if (message.includes('timeout')) {
    return {
      code: ErrorCodes.TIMEOUT_ERROR,
      message: 'The request timed out. Please try again.',
      recoverable: true,
    };
  }

  // Generic error
  return {
    code: ErrorCodes.UNKNOWN_ERROR,
    message: error.message || 'An unexpected error occurred.',
    recoverable: false,
  };
}

/**
 * Get a user-friendly error message from any error
 *
 * @param error - Any error type
 * @returns User-friendly error message string
 */
export function getErrorMessage(error: unknown): string {
  return handleApiError(error).message;
}

/**
 * Check if an error is recoverable (can be retried)
 *
 * @param error - Any error type
 * @returns Whether the error is recoverable
 */
export function isRecoverableError(error: unknown): boolean {
  return handleApiError(error).recoverable;
}

/**
 * Check if error is a specific type
 *
 * @param error - Any error type
 * @param code - Error code to check against
 * @returns Whether the error matches the code
 */
export function isErrorType(error: unknown, code: keyof typeof ErrorCodes): boolean {
  return handleApiError(error).code === code;
}

/**
 * Log error with structured context
 * Logs to console in development and tracks in production
 *
 * @param error - Any error type
 * @param context - Additional context for logging
 */
export function logError(error: unknown, context?: Record<string, unknown>): void {
  const apiError = handleApiError(error);

  // Always log to console in development
  if (process.env.NODE_ENV === 'development') {
    console.error('[API Error]', {
      ...apiError,
      originalError: error,
      context,
    });
  }

  // Track error in production (if tracking is configured)
  trackError(error, {
    extra: context,
    tags: {
      errorCode: apiError.code,
      recoverable: String(apiError.recoverable)
    }
  });
}

const errorHandler = {
  // Core error handling
  handleApiError,
  getErrorMessage,
  isRecoverableError,
  isErrorType,
  logError,
  ErrorCodes,
  // Error tracking
  configureErrorTracking,
  setErrorTrackingContext,
  clearErrorTrackingContext,
  trackError,
};

export default errorHandler;
