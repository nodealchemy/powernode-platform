/**
 * Retry Utilities for Frontend API Calls
 *
 * Provides exponential backoff retry logic for transient failures.
 * Use this for API calls that may fail due to network issues, rate limiting,
 * or temporary service unavailability.
 */

import { handleApiError, isRecoverableError, ErrorCodes, ApiError } from '@/shared/services/errorHandler';

/**
 * Configuration for retry behavior
 */
export interface RetryConfig {
  /** Maximum number of retry attempts (default: 3) */
  maxRetries?: number;
  /** Initial delay in milliseconds (default: 1000) */
  initialDelay?: number;
  /** Maximum delay in milliseconds (default: 30000) */
  maxDelay?: number;
  /** Multiplier for exponential backoff (default: 2) */
  backoffMultiplier?: number;
  /** HTTP status codes that should trigger retry (default: [429, 503, 504]) */
  retryStatusCodes?: number[];
  /** Callback for retry attempts */
  onRetry?: (attempt: number, error: ApiError, nextDelayMs: number) => void;
}

const DEFAULT_CONFIG: Required<RetryConfig> = {
  maxRetries: 3,
  initialDelay: 1000,
  maxDelay: 30000,
  backoffMultiplier: 2,
  retryStatusCodes: [429, 503, 504],
  onRetry: () => {},
};

/**
 * Result of a retry operation
 */
export type RetryResult<T> = {
  success: true;
  data: T;
  attempts: number;
} | {
  success: false;
  error: ApiError;
  attempts: number;
}

/**
 * Check if an error should trigger a retry
 */
function shouldRetry(error: unknown, config: Required<RetryConfig>): boolean {
  // First check if the error is generally recoverable
  if (!isRecoverableError(error)) {
    return false;
  }

  const apiError = handleApiError(error);

  // Check for specific error codes that should retry
  if (apiError.code === ErrorCodes.RATE_LIMITED ||
      apiError.code === ErrorCodes.SERVICE_UNAVAILABLE ||
      apiError.code === ErrorCodes.NETWORK_ERROR ||
      apiError.code === ErrorCodes.TIMEOUT_ERROR) {
    return true;
  }

  // Check HTTP status codes
  if (apiError.statusCode && config.retryStatusCodes.includes(apiError.statusCode)) {
    return true;
  }

  return false;
}

/**
 * Calculate delay for next retry with exponential backoff and jitter
 */
function calculateDelay(attempt: number, config: Required<RetryConfig>): number {
  // Exponential backoff: initialDelay * (multiplier ^ attempt)
  const exponentialDelay = config.initialDelay * Math.pow(config.backoffMultiplier, attempt);

  // Add jitter (±25% of delay) to prevent thundering herd
  const jitter = exponentialDelay * 0.25 * (Math.random() * 2 - 1);

  const delay = Math.min(exponentialDelay + jitter, config.maxDelay);

  return Math.round(delay);
}

/**
 * Sleep for specified milliseconds
 */
function sleep(ms: number): Promise<void> {
  return new Promise(resolve => setTimeout(resolve, ms));
}

/**
 * Execute an async operation with retry logic
 *
 * @param operation - Async function to execute
 * @param config - Retry configuration
 * @returns RetryResult with data or error
 *
 * @example
 * ```typescript
 * const result = await withRetry(
 *   () => api.get('/users'),
 *   {
 *     maxRetries: 3,
 *     onRetry: (attempt, error, delay) => {
 *       console.log(`Retrying in ${delay}ms (attempt ${attempt})...`);
 *     }
 *   }
 * );
 *
 * if (result.success) {
 *   console.log('Data:', result.data);
 * } else {
 *   console.error('Failed after', result.attempts, 'attempts:', result.error.message);
 * }
 * ```
 */
export async function withRetry<T>(
  operation: () => Promise<T>,
  config?: RetryConfig
): Promise<RetryResult<T>> {
  const mergedConfig = { ...DEFAULT_CONFIG, ...config };
  let lastError: ApiError | null = null;
  let attempts = 0;

  for (let attempt = 0; attempt <= mergedConfig.maxRetries; attempt++) {
    attempts = attempt + 1;

    try {
      const data = await operation();
      return { success: true, data, attempts };
    } catch (error) {
      lastError = handleApiError(error);

      // Check if we should retry
      if (attempt < mergedConfig.maxRetries && shouldRetry(error, mergedConfig)) {
        const delay = calculateDelay(attempt, mergedConfig);

        // Notify callback
        mergedConfig.onRetry(attempt + 1, lastError, delay);

        await sleep(delay);
        continue;
      }

      // No more retries
      break;
    }
  }

  return {
    success: false,
    error: lastError!,
    attempts
  };
}

/**
 * Create a retry wrapper for an async function
 * Returns a function that will automatically retry on failure
 *
 * @param operation - Async function to wrap
 * @param config - Retry configuration
 * @returns Wrapped function with retry logic
 *
 * @example
 * ```typescript
 * const fetchUserWithRetry = createRetryWrapper(
 *   (userId: string) => api.get(`/users/${userId}`),
 *   { maxRetries: 3 }
 * );
 *
 * const result = await fetchUserWithRetry('123');
 * ```
 */
export function createRetryWrapper<TArgs extends unknown[], TResult>(
  operation: (...args: TArgs) => Promise<TResult>,
  config?: RetryConfig
): (...args: TArgs) => Promise<RetryResult<TResult>> {
  return (...args: TArgs) => withRetry(() => operation(...args), config);
}

/**
 * Higher-order function to add retry logic to an API service method
 * Throws on failure (use withRetry for result-based error handling)
 *
 * @param operation - Async function to wrap
 * @param config - Retry configuration
 * @returns Wrapped function that throws on ultimate failure
 *
 * @example
 * ```typescript
 * class UserService {
 *   fetchUser = retryable(
 *     (id: string) => api.get(`/users/${id}`),
 *     { maxRetries: 2 }
 *   );
 * }
 * ```
 */
export function retryable<TArgs extends unknown[], TResult>(
  operation: (...args: TArgs) => Promise<TResult>,
  config?: RetryConfig
): (...args: TArgs) => Promise<TResult> {
  return async (...args: TArgs) => {
    const result = await withRetry(() => operation(...args), config);

    if (result.success) {
      return result.data;
    }

    // Re-throw for traditional try-catch handling
    throw new Error(result.error.message);
  };
}

const retryUtils = {
  withRetry,
  createRetryWrapper,
  retryable,
};

export default retryUtils;
