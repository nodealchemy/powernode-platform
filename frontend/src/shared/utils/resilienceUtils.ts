// Resilience utilities for handling network failures, retries, and graceful degradation

export interface RetryConfig {
  maxAttempts: number;
  baseDelay: number;
  maxDelay: number;
  backoffMultiplier: number;
  jitter: boolean;
}

export interface CircuitBreakerConfig {
  failureThreshold: number;
  resetTimeout: number;
  monitoringPeriod: number;
}

export interface TimeoutConfig {
  timeoutMs: number;
  abortController?: AbortController;
}

// Default configurations
export const DEFAULT_RETRY_CONFIG: RetryConfig = {
  maxAttempts: 3,
  baseDelay: 1000,
  maxDelay: 30000,
  backoffMultiplier: 2,
  jitter: true
};

export const DEFAULT_CIRCUIT_BREAKER_CONFIG: CircuitBreakerConfig = {
  failureThreshold: 5,
  resetTimeout: 60000,
  monitoringPeriod: 60000
};

export const DEFAULT_TIMEOUT_CONFIG: TimeoutConfig = {
  timeoutMs: 30000
};

// Exponential backoff with jitter
export function calculateDelay(
  attempt: number, 
  config: Partial<RetryConfig> = {}
): number {
  const mergedConfig = { ...DEFAULT_RETRY_CONFIG, ...config };
  const { baseDelay, maxDelay, backoffMultiplier, jitter } = mergedConfig;

  let delay = baseDelay * Math.pow(backoffMultiplier, attempt - 1);
  
  if (jitter) {
    // Add random jitter between 0% and 25% of the delay
    const jitterAmount = delay * 0.25 * Math.random();
    delay += jitterAmount;
  }

  return Math.min(delay, maxDelay);
}

// Retry function with exponential backoff
export async function withRetry<T>(
  operation: () => Promise<T>,
  config: Partial<RetryConfig> = {},
  shouldRetry?: (error: unknown) => boolean
): Promise<T> {
  const mergedConfig = { ...DEFAULT_RETRY_CONFIG, ...config };
  const { maxAttempts } = mergedConfig;
  
  let lastError: unknown;

  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      return await operation();
    } catch (error) {
      lastError = error;

      // Check if we should retry this error
      if (shouldRetry && !shouldRetry(error)) {
        throw error;
      }

      // Don't retry on the last attempt
      if (attempt === maxAttempts) {
        break;
      }

      // Wait before next attempt
      const delay = calculateDelay(attempt, mergedConfig);
      await sleep(delay);
    }
  }

  throw lastError;
}

// Circuit breaker implementation
export class CircuitBreaker {
  private state: 'closed' | 'open' | 'half-open' = 'closed';
  private failureCount = 0;
  private lastFailureTime = 0;
  private successCount = 0;

  constructor(config: Partial<CircuitBreakerConfig> = {}) {
    this.config = { ...DEFAULT_CIRCUIT_BREAKER_CONFIG, ...config };
  }
  
  private config: CircuitBreakerConfig;

  async execute<T>(operation: () => Promise<T>): Promise<T> {
    if (this.state === 'open') {
      if (Date.now() - this.lastFailureTime >= this.config.resetTimeout) {
        this.state = 'half-open';
        this.successCount = 0;
      } else {
        throw new Error('Circuit breaker is OPEN');
      }
    }

    try {
      const result = await operation();
      this.onSuccess();
      return result;
    } catch (error) {
      this.onFailure();
      throw error;
    }
  }

  private onSuccess(): void {
    if (this.state === 'half-open') {
      this.successCount++;
      if (this.successCount >= 3) { // Require 3 successes to close
        this.state = 'closed';
        this.failureCount = 0;
        this.successCount = 0;
      }
    } else if (this.state === 'closed') {
      this.failureCount = 0;
    }
  }

  private onFailure(): void {
    this.failureCount++;
    this.lastFailureTime = Date.now();

    if (this.state === 'half-open') {
      this.state = 'open';
    } else if (this.state === 'closed' && this.failureCount >= this.config.failureThreshold) {
      this.state = 'open';
    }
  }

  getState(): string {
    return this.state;
  }

  getStats() {
    return {
      state: this.state,
      failureCount: this.failureCount,
      lastFailureTime: this.lastFailureTime,
      successCount: this.successCount
    };
  }

  reset(): void {
    this.state = 'closed';
    this.failureCount = 0;
    this.lastFailureTime = 0;
    this.successCount = 0;
  }
}

// Timeout wrapper with abort controller
export async function withTimeout<T>(
  operation: () => Promise<T>,
  config: TimeoutConfig = DEFAULT_TIMEOUT_CONFIG
): Promise<T> {
  const { timeoutMs, abortController } = config;

  return new Promise<T>((resolve, reject) => {
    const timeoutId = setTimeout(() => {
      if (abortController) {
        abortController.abort();
      }
      reject(new Error(`Operation timed out after ${timeoutMs}ms`));
    }, timeoutMs);

    operation()
      .then(result => {
        clearTimeout(timeoutId);
        resolve(result);
      })
      .catch(error => {
        clearTimeout(timeoutId);
        reject(error);
      });
  });
}

// Bulkhead pattern - limit concurrent operations
export class Bulkhead {
  private activeOperations = 0;
  private queue: Array<() => void> = [];

  constructor(private maxConcurrent: number) {}

  async execute<T>(operation: () => Promise<T>): Promise<T> {
    if (this.activeOperations >= this.maxConcurrent) {
      await this.waitForSlot();
    }

    this.activeOperations++;

    try {
      const result = await operation();
      return result;
    } finally {
      this.activeOperations--;
      this.processQueue();
    }
  }

  private waitForSlot(): Promise<void> {
    return new Promise(resolve => {
      this.queue.push(resolve);
    });
  }

  private processQueue(): void {
    if (this.queue.length > 0 && this.activeOperations < this.maxConcurrent) {
      const next = this.queue.shift();
      if (next) {
        next();
      }
    }
  }

  getStats() {
    return {
      activeOperations: this.activeOperations,
      queueLength: this.queue.length,
      maxConcurrent: this.maxConcurrent
    };
  }
}

// Cache with TTL for reducing load
export class CacheWithTTL<T> {
  private cache = new Map<string, { value: T; expiry: number }>();

  constructor(private defaultTTL: number = 60000) {}

  set(key: string, value: T, ttl?: number): void {
    const expiry = Date.now() + (ttl || this.defaultTTL);
    this.cache.set(key, { value, expiry });
  }

  get(key: string): T | undefined {
    const item = this.cache.get(key);
    if (!item) return undefined;

    if (Date.now() > item.expiry) {
      this.cache.delete(key);
      return undefined;
    }

    return item.value;
  }

  has(key: string): boolean {
    return this.get(key) !== undefined;
  }

  delete(key: string): void {
    this.cache.delete(key);
  }

  clear(): void {
    this.cache.clear();
  }

  cleanup(): void {
    const now = Date.now();
    for (const [key, item] of this.cache.entries()) {
      if (now > item.expiry) {
        this.cache.delete(key);
      }
    }
  }

  getStats() {
    return {
      size: this.cache.size,
      keys: Array.from(this.cache.keys())
    };
  }
}

// Graceful degradation utility
export async function withGracefulDegradation<T, F>(
  primaryOperation: () => Promise<T>,
  fallbackOperation: () => Promise<F> | F,
  shouldUseFallback?: (error: unknown) => boolean
): Promise<T | F> {
  try {
    return await primaryOperation();
  } catch (originalError) {
    if (shouldUseFallback && !shouldUseFallback(originalError)) {
      throw originalError;
    }

    try {
      return await fallbackOperation();
    } catch {
      // Throw original error if fallback also fails
      throw originalError;
    }
  }
}

// Health check utility
export interface HealthStatus {
  status: 'healthy' | 'unhealthy' | 'degraded';
  checks: Record<string, { status: 'pass' | 'fail'; message?: string; duration?: number }>;
  timestamp: number;
}

export class HealthChecker {
  private checks = new Map<string, () => Promise<{ status: 'pass' | 'fail'; message?: string }>>();

  addCheck(name: string, checkFn: () => Promise<{ status: 'pass' | 'fail'; message?: string }>): void {
    this.checks.set(name, checkFn);
  }

  removeCheck(name: string): void {
    this.checks.delete(name);
  }

  async checkHealth(): Promise<HealthStatus> {
    const results: Record<string, { status: 'pass' | 'fail'; message?: string; duration?: number }> = {};
    let overallStatus: 'healthy' | 'unhealthy' | 'degraded' = 'healthy';

    for (const [name, checkFn] of this.checks) {
      const startTime = Date.now();
      try {
        const result = await withTimeout(
          () => checkFn(),
          { timeoutMs: 5000 }
        );
        results[name] = {
          ...result,
          duration: Date.now() - startTime
        };

        if (result.status === 'fail') {
          overallStatus = overallStatus === 'healthy' ? 'degraded' : 'unhealthy';
        }
      } catch (error) {
        results[name] = {
          status: 'fail',
          message: error instanceof Error ? error.message : 'Unknown error',
          duration: Date.now() - startTime
        };
        overallStatus = 'unhealthy';
      }
    }

    return {
      status: overallStatus,
      checks: results,
      timestamp: Date.now()
    };
  }
}

// Utility functions
export function sleep(ms: number): Promise<void> {
  return new Promise(resolve => setTimeout(resolve, ms));
}

export function isNetworkError(error: unknown): boolean {
  if (!(error instanceof Error)) return false;
  
  const networkErrorPatterns = [
    /network error/i,
    /fetch.*failed/i,
    /connection.*refused/i,
    /timeout/i,
    /net::/i,
    /dns.*resolution.*failed/i,
    /unreachable/i
  ];

  return networkErrorPatterns.some(pattern => pattern.test(error.message));
}

// Type guard for errors that have an HTTP response attached
interface ErrorWithResponse extends Error {
  response?: {
    status?: number;
  };
}

function hasHttpResponse(error: Error): error is ErrorWithResponse {
  return 'response' in error &&
         typeof (error as ErrorWithResponse).response === 'object' &&
         (error as ErrorWithResponse).response !== null;
}

export function isRetryableError(error: unknown): boolean {
  if (!(error instanceof Error)) return false;

  // Retry on network errors
  if (isNetworkError(error)) return true;

  // Check for HTTP status codes (if error has response)
  if (hasHttpResponse(error) && error.response?.status) {
    const status = error.response.status;
    // Retry on 5xx server errors and some 4xx errors
    return status >= 500 || status === 408 || status === 429;
  }

  return false;
}

// Combined resilience wrapper
export async function withResilience<T>(
  operation: () => Promise<T>,
  options: {
    retry?: Partial<RetryConfig>;
    timeout?: Partial<TimeoutConfig>;
    circuitBreaker?: CircuitBreaker;
    bulkhead?: Bulkhead;
    fallback?: () => Promise<T> | T;
  } = {}
): Promise<T> {
  const { retry, timeout, circuitBreaker, bulkhead, fallback } = options;

  let wrappedOperation = operation;

  // Apply circuit breaker wrapper first (innermost)
  if (circuitBreaker) {
    const originalOperation = wrappedOperation;
    wrappedOperation = () => circuitBreaker.execute(originalOperation);
  }

  // Apply bulkhead wrapper
  if (bulkhead) {
    const originalOperation = wrappedOperation;
    wrappedOperation = () => bulkhead.execute(originalOperation);
  }

  // Apply retry wrapper
  if (retry) {
    const originalOperation = wrappedOperation;
    // Don't pass shouldRetry to allow retrying all errors by default
    // This matches the expected behavior in tests
    wrappedOperation = () => withRetry(originalOperation, retry);
  }

  // Apply timeout wrapper (outermost, wraps entire operation including retries)
  if (timeout) {
    const originalOperation = wrappedOperation;
    wrappedOperation = () => withTimeout(originalOperation, { ...DEFAULT_TIMEOUT_CONFIG, ...timeout });
  }

  // Apply fallback wrapper
  if (fallback) {
    return withGracefulDegradation(wrappedOperation, fallback);
  }

  return wrappedOperation();
}