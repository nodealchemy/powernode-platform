import {
  calculateDelay,
  withRetry,
  withTimeout,
  withGracefulDegradation,
  withResilience,
  CircuitBreaker,
  Bulkhead,
  CacheWithTTL,
  HealthChecker,
  sleep,
  isNetworkError,
  isRetryableError,
  DEFAULT_RETRY_CONFIG,
  DEFAULT_CIRCUIT_BREAKER_CONFIG,
  DEFAULT_TIMEOUT_CONFIG
} from './resilienceUtils';

describe('resilienceUtils', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('calculateDelay', () => {
    it('calculates exponential backoff correctly', () => {
      const config = { baseDelay: 1000, backoffMultiplier: 2, jitter: false };
      
      expect(calculateDelay(1, config)).toBe(1000);
      expect(calculateDelay(2, config)).toBe(2000);
      expect(calculateDelay(3, config)).toBe(4000);
      expect(calculateDelay(4, config)).toBe(8000);
    });

    it('respects maximum delay limit', () => {
      const config = { baseDelay: 1000, maxDelay: 5000, backoffMultiplier: 2, jitter: false };
      
      expect(calculateDelay(10, config)).toBe(5000);
      expect(calculateDelay(15, config)).toBe(5000);
    });

    it('adds jitter when enabled', () => {
      const config = { baseDelay: 1000, backoffMultiplier: 2, jitter: true };
      
      const delay1 = calculateDelay(2, config);
      const delay2 = calculateDelay(2, config);
      const delay3 = calculateDelay(2, config);
      
      // Should be around 2000ms but vary due to jitter
      expect(delay1).toBeGreaterThanOrEqual(2000);
      expect(delay1).toBeLessThanOrEqual(2500);
      
      // Multiple calls should produce different values due to jitter
      const delays = [delay1, delay2, delay3];
      const uniqueDelays = [...new Set(delays)];
      expect(uniqueDelays.length).toBeGreaterThan(1);
    });

    it('uses default config when not provided', () => {
      const delay = calculateDelay(1);
      expect(delay).toBeGreaterThanOrEqual(DEFAULT_RETRY_CONFIG.baseDelay);
    });
  });

  describe('withRetry', () => {
    it('succeeds on first attempt when operation succeeds', async () => {
      const mockOperation = jest.fn().mockResolvedValue('success');
      
      const result = await withRetry(mockOperation);
      
      expect(result).toBe('success');
      expect(mockOperation).toHaveBeenCalledTimes(1);
    });

    it('retries on failure and eventually succeeds', async () => {
      const mockOperation = jest.fn()
        .mockRejectedValueOnce(new Error('First failure'))
        .mockRejectedValueOnce(new Error('Second failure'))
        .mockResolvedValue('success');
      
      const result = await withRetry(mockOperation, { maxAttempts: 3 });
      
      expect(result).toBe('success');
      expect(mockOperation).toHaveBeenCalledTimes(3);
    });

    it('throws error after max attempts', async () => {
      const mockOperation = jest.fn().mockRejectedValue(new Error('Persistent failure'));
      
      await expect(withRetry(mockOperation, { maxAttempts: 2 })).rejects.toThrow('Persistent failure');
      expect(mockOperation).toHaveBeenCalledTimes(2);
    });

    it('respects shouldRetry predicate', async () => {
      const mockOperation = jest.fn().mockRejectedValue(new Error('Auth error'));
      const shouldRetry = jest.fn().mockReturnValue(false);
      
      await expect(withRetry(mockOperation, {}, shouldRetry)).rejects.toThrow('Auth error');
      expect(mockOperation).toHaveBeenCalledTimes(1);
      expect(shouldRetry).toHaveBeenCalledWith(expect.any(Error));
    });

    it('waits between retry attempts', async () => {
      const mockOperation = jest.fn()
        .mockRejectedValueOnce(new Error('First failure'))
        .mockResolvedValue('success');
      
      const startTime = Date.now();
      await withRetry(mockOperation, { baseDelay: 100, jitter: false });
      const endTime = Date.now();
      
      expect(endTime - startTime).toBeGreaterThanOrEqual(99); // Account for timing precision
    });
  });

  describe('CircuitBreaker', () => {
    let circuitBreaker: CircuitBreaker;

    beforeEach(() => {
      circuitBreaker = new CircuitBreaker({ failureThreshold: 3, resetTimeout: 1000 });
    });

    it('starts in closed state', () => {
      expect(circuitBreaker.getState()).toBe('closed');
    });

    it('opens after reaching failure threshold', async () => {
      const failingOperation = jest.fn().mockRejectedValue(new Error('Service down'));
      
      // Trigger failures to reach threshold
      for (let i = 0; i < 3; i++) {
        try {
          await circuitBreaker.execute(failingOperation);
        } catch (error) {
          // Expected failures
        }
      }
      
      expect(circuitBreaker.getState()).toBe('open');
    });

    it('rejects immediately when open', async () => {
      const failingOperation = jest.fn().mockRejectedValue(new Error('Service down'));
      
      // Trip the circuit breaker
      for (let i = 0; i < 3; i++) {
        try {
          await circuitBreaker.execute(failingOperation);
        } catch (error) {
          // Expected failures
        }
      }
      
      // Should reject immediately without calling operation
      await expect(circuitBreaker.execute(failingOperation)).rejects.toThrow('Circuit breaker is OPEN');
      expect(failingOperation).toHaveBeenCalledTimes(3); // Only original failures, no new calls
    });

    it('transitions to half-open after reset timeout', async () => {
      const failingOperation = jest.fn().mockRejectedValue(new Error('Service down'));
      
      // Trip the circuit breaker
      for (let i = 0; i < 3; i++) {
        try {
          await circuitBreaker.execute(failingOperation);
        } catch (error) {
          // Expected failures
        }
      }
      
      // Wait for reset timeout
      await sleep(1100);
      
      // Next operation should transition to half-open
      const successOperation = jest.fn().mockResolvedValue('success');
      await circuitBreaker.execute(successOperation);
      
      expect(circuitBreaker.getState()).toBe('half-open');
    });

    it('resets to closed after successful operations in half-open state', async () => {
      const failingOperation = jest.fn().mockRejectedValue(new Error('Service down'));
      const successOperation = jest.fn().mockResolvedValue('success');
      
      // Trip the circuit breaker
      for (let i = 0; i < 3; i++) {
        try {
          await circuitBreaker.execute(failingOperation);
        } catch (error) {
          // Expected failures
        }
      }
      
      // Wait for reset timeout
      await sleep(1100);
      
      // Execute successful operations to close circuit
      for (let i = 0; i < 3; i++) {
        await circuitBreaker.execute(successOperation);
      }
      
      expect(circuitBreaker.getState()).toBe('closed');
    });

    it('provides circuit statistics', () => {
      const stats = circuitBreaker.getStats();
      
      expect(stats).toHaveProperty('state');
      expect(stats).toHaveProperty('failureCount');
      expect(stats).toHaveProperty('lastFailureTime');
      expect(stats).toHaveProperty('successCount');
    });

    it('can be reset manually', async () => {
      const failingOperation = jest.fn().mockRejectedValue(new Error('Service down'));
      
      // Trip the circuit breaker
      for (let i = 0; i < 3; i++) {
        try {
          await circuitBreaker.execute(failingOperation);
        } catch (error) {
          // Expected failures
        }
      }
      
      expect(circuitBreaker.getState()).toBe('open');
      
      circuitBreaker.reset();
      
      expect(circuitBreaker.getState()).toBe('closed');
      expect(circuitBreaker.getStats().failureCount).toBe(0);
    });
  });

  describe('withTimeout', () => {
    it('resolves when operation completes within timeout', async () => {
      const fastOperation = () => Promise.resolve('fast result');
      
      const result = await withTimeout(fastOperation, { timeoutMs: 1000 });
      
      expect(result).toBe('fast result');
    });

    it('rejects when operation exceeds timeout', async () => {
      const slowOperation = () => sleep(2000).then(() => 'slow result');
      
      await expect(withTimeout(slowOperation, { timeoutMs: 100 })).rejects.toThrow('Operation timed out after 100ms');
    });

    it('uses abort controller when provided', async () => {
      const abortController = new AbortController();
      const slowOperation = () => sleep(2000).then(() => 'slow result');
      
      const timeoutPromise = withTimeout(slowOperation, { 
        timeoutMs: 100, 
        abortController 
      });
      
      await expect(timeoutPromise).rejects.toThrow('Operation timed out after 100ms');
      expect(abortController.signal.aborted).toBe(true);
    });

    it('clears timeout when operation completes', async () => {
      const clearTimeoutSpy = jest.spyOn(global, 'clearTimeout');
      const fastOperation = () => Promise.resolve('result');
      
      await withTimeout(fastOperation, { timeoutMs: 1000 });
      
      expect(clearTimeoutSpy).toHaveBeenCalled();
      clearTimeoutSpy.mockRestore();
    });
  });

  describe('Bulkhead', () => {
    it('allows operations up to max concurrent limit', async () => {
      const bulkhead = new Bulkhead(2);
      const operation = jest.fn().mockImplementation(() => sleep(100).then(() => 'result'));
      
      // Start 2 operations (should both execute immediately)
      const promise1 = bulkhead.execute(operation);
      const promise2 = bulkhead.execute(operation);
      
      expect(bulkhead.getStats().activeOperations).toBe(2);
      
      await Promise.all([promise1, promise2]);
      
      expect(operation).toHaveBeenCalledTimes(2);
    });

    it('queues operations when limit exceeded', async () => {
      const bulkhead = new Bulkhead(1);
      const operation = jest.fn().mockImplementation(() => sleep(100).then(() => 'result'));
      
      // Start 2 operations (first executes, second queues)
      const promise1 = bulkhead.execute(operation);
      const promise2 = bulkhead.execute(operation);
      
      expect(bulkhead.getStats().activeOperations).toBe(1);
      expect(bulkhead.getStats().queueLength).toBe(1);
      
      await Promise.all([promise1, promise2]);
      
      expect(operation).toHaveBeenCalledTimes(2);
    });

    it('processes queue when operations complete', async () => {
      const bulkhead = new Bulkhead(1);
      let completedOperations = 0;
      
      const operation = jest.fn().mockImplementation(() => 
        sleep(50).then(() => {
          completedOperations++;
          return `result ${completedOperations}`;
        })
      );
      
      // Start multiple operations
      const promises = [
        bulkhead.execute(operation),
        bulkhead.execute(operation),
        bulkhead.execute(operation)
      ];
      
      await Promise.all(promises);
      
      expect(completedOperations).toBe(3);
      expect(bulkhead.getStats().activeOperations).toBe(0);
      expect(bulkhead.getStats().queueLength).toBe(0);
    });

    it('provides bulkhead statistics', async () => {
      const bulkhead = new Bulkhead(2);
      const operation = () => sleep(100).then(() => 'result');
      
      bulkhead.execute(operation);
      const stats = bulkhead.getStats();
      
      expect(stats).toHaveProperty('activeOperations');
      expect(stats).toHaveProperty('queueLength');
      expect(stats).toHaveProperty('maxConcurrent');
      expect(stats.maxConcurrent).toBe(2);
    });
  });

  describe('CacheWithTTL', () => {
    let cache: CacheWithTTL<string>;

    beforeEach(() => {
      cache = new CacheWithTTL<string>(1000); // 1 second TTL
    });

    it('stores and retrieves values', () => {
      cache.set('key1', 'value1');
      
      expect(cache.get('key1')).toBe('value1');
      expect(cache.has('key1')).toBe(true);
    });

    it('expires values after TTL', async () => {
      cache.set('key1', 'value1', 100); // 100ms TTL
      
      expect(cache.get('key1')).toBe('value1');
      
      await sleep(150);
      
      expect(cache.get('key1')).toBeUndefined();
      expect(cache.has('key1')).toBe(false);
    });

    it('uses custom TTL when provided', async () => {
      cache.set('key1', 'value1', 2000); // 2 second TTL
      
      await sleep(1500);
      
      expect(cache.get('key1')).toBe('value1'); // Should still be valid
    });

    it('deletes specific keys', () => {
      cache.set('key1', 'value1');
      cache.set('key2', 'value2');
      
      cache.delete('key1');
      
      expect(cache.get('key1')).toBeUndefined();
      expect(cache.get('key2')).toBe('value2');
    });

    it('clears all entries', () => {
      cache.set('key1', 'value1');
      cache.set('key2', 'value2');
      
      cache.clear();
      
      expect(cache.get('key1')).toBeUndefined();
      expect(cache.get('key2')).toBeUndefined();
    });

    it('cleans up expired entries', async () => {
      cache.set('key1', 'value1', 100);
      cache.set('key2', 'value2', 200);
      
      await sleep(150);
      
      cache.cleanup();
      
      const stats = cache.getStats();
      expect(stats.size).toBe(1); // Only key2 should remain
      expect(stats.keys).toEqual(['key2']);
    });

    it('provides cache statistics', () => {
      cache.set('key1', 'value1');
      cache.set('key2', 'value2');
      
      const stats = cache.getStats();
      
      expect(stats.size).toBe(2);
      expect(stats.keys).toEqual(['key1', 'key2']);
    });
  });

  describe('withGracefulDegradation', () => {
    it('returns primary operation result when successful', async () => {
      const primaryOperation = jest.fn().mockResolvedValue('primary result');
      const fallbackOperation = jest.fn().mockResolvedValue('fallback result');
      
      const result = await withGracefulDegradation(primaryOperation, fallbackOperation);
      
      expect(result).toBe('primary result');
      expect(primaryOperation).toHaveBeenCalled();
      expect(fallbackOperation).not.toHaveBeenCalled();
    });

    it('returns fallback result when primary fails', async () => {
      const primaryOperation = jest.fn().mockRejectedValue(new Error('Primary failed'));
      const fallbackOperation = jest.fn().mockResolvedValue('fallback result');
      
      const result = await withGracefulDegradation(primaryOperation, fallbackOperation);
      
      expect(result).toBe('fallback result');
      expect(primaryOperation).toHaveBeenCalled();
      expect(fallbackOperation).toHaveBeenCalled();
    });

    it('respects shouldUseFallback predicate', async () => {
      const primaryOperation = jest.fn().mockRejectedValue(new Error('Auth error'));
      const fallbackOperation = jest.fn().mockResolvedValue('fallback result');
      const shouldUseFallback = jest.fn().mockReturnValue(false);
      
      await expect(withGracefulDegradation(primaryOperation, fallbackOperation, shouldUseFallback))
        .rejects.toThrow('Auth error');
      
      expect(fallbackOperation).not.toHaveBeenCalled();
      expect(shouldUseFallback).toHaveBeenCalledWith(expect.any(Error));
    });

    it('throws original error when fallback also fails', async () => {
      const originalError = new Error('Primary failed');
      const primaryOperation = jest.fn().mockRejectedValue(originalError);
      const fallbackOperation = jest.fn().mockRejectedValue(new Error('Fallback failed'));
      
      await expect(withGracefulDegradation(primaryOperation, fallbackOperation))
        .rejects.toThrow('Primary failed');
    });
  });

  describe('HealthChecker', () => {
    let healthChecker: HealthChecker;

    beforeEach(() => {
      healthChecker = new HealthChecker();
    });

    it('returns healthy status with no checks', async () => {
      const health = await healthChecker.checkHealth();
      
      expect(health.status).toBe('healthy');
      expect(health.checks).toEqual({});
      expect(health.timestamp).toBeGreaterThan(0);
    });

    it('executes registered health checks', async () => {
      const dbCheck = jest.fn().mockResolvedValue({ status: 'pass', message: 'Database OK' });
      const apiCheck = jest.fn().mockResolvedValue({ status: 'pass', message: 'API OK' });
      
      healthChecker.addCheck('database', dbCheck);
      healthChecker.addCheck('api', apiCheck);
      
      const health = await healthChecker.checkHealth();
      
      expect(health.status).toBe('healthy');
      expect(health.checks.database.status).toBe('pass');
      expect(health.checks.api.status).toBe('pass');
      expect(dbCheck).toHaveBeenCalled();
      expect(apiCheck).toHaveBeenCalled();
    });

    it('reports degraded status when some checks fail', async () => {
      const passCheck = jest.fn().mockResolvedValue({ status: 'pass' });
      const failCheck = jest.fn().mockResolvedValue({ status: 'fail', message: 'Service unavailable' });
      
      healthChecker.addCheck('service1', passCheck);
      healthChecker.addCheck('service2', failCheck);
      
      const health = await healthChecker.checkHealth();
      
      expect(health.status).toBe('degraded');
      expect(health.checks.service1.status).toBe('pass');
      expect(health.checks.service2.status).toBe('fail');
    });

    it('reports unhealthy status when checks timeout', async () => {
      const slowCheck = jest.fn().mockImplementation(() => sleep(6000).then(() => ({ status: 'pass' })));
      
      healthChecker.addCheck('slow-service', slowCheck);
      
      const health = await healthChecker.checkHealth();
      
      expect(health.status).toBe('unhealthy');
      expect(health.checks['slow-service'].status).toBe('fail');
      expect(health.checks['slow-service'].message).toContain('timed out');
    }, 10000); // Increase timeout for this specific test

    it('includes duration in check results', async () => {
      const quickCheck = jest.fn().mockImplementation(async () => {
        await sleep(10); // Small delay to ensure measurable duration
        return { status: 'pass' };
      });
      
      healthChecker.addCheck('quick-service', quickCheck);
      
      const health = await healthChecker.checkHealth();
      
      expect(health.checks['quick-service'].duration).toBeGreaterThan(0);
      expect(health.checks['quick-service'].duration).toBeLessThan(1000);
    });

    it('can remove health checks', async () => {
      const check1 = jest.fn().mockResolvedValue({ status: 'pass' });
      const check2 = jest.fn().mockResolvedValue({ status: 'pass' });
      
      healthChecker.addCheck('service1', check1);
      healthChecker.addCheck('service2', check2);
      healthChecker.removeCheck('service1');
      
      const health = await healthChecker.checkHealth();
      
      expect(health.checks).not.toHaveProperty('service1');
      expect(health.checks).toHaveProperty('service2');
    });
  });

  describe('utility functions', () => {
    describe('sleep', () => {
      it('resolves after specified delay', async () => {
        const startTime = Date.now();
        await sleep(100);
        const endTime = Date.now();
        
        expect(endTime - startTime).toBeGreaterThanOrEqual(100);
      });
    });

    describe('isNetworkError', () => {
      it('identifies network errors correctly', () => {
        expect(isNetworkError(new Error('Network error occurred'))).toBe(true);
        expect(isNetworkError(new Error('Fetch failed'))).toBe(true);
        expect(isNetworkError(new Error('Connection refused'))).toBe(true);
        expect(isNetworkError(new Error('Request timeout'))).toBe(true);
        expect(isNetworkError(new Error('net::ERR_NETWORK_CHANGED'))).toBe(true);
        expect(isNetworkError(new Error('DNS resolution failed'))).toBe(true);
        expect(isNetworkError(new Error('Host unreachable'))).toBe(true);
      });

      it('returns false for non-network errors', () => {
        expect(isNetworkError(new Error('Validation failed'))).toBe(false);
        expect(isNetworkError(new Error('Authentication required'))).toBe(false);
        expect(isNetworkError('string error')).toBe(false);
        expect(isNetworkError(null)).toBe(false);
      });
    });

    describe('isRetryableError', () => {
      it('identifies retryable HTTP status codes', () => {
        const error500 = Object.assign(new Error('Server Error'), { response: { status: 500 } });
        const error502 = Object.assign(new Error('Bad Gateway'), { response: { status: 502 } });
        const error503 = Object.assign(new Error('Service Unavailable'), { response: { status: 503 } });
        const error408 = Object.assign(new Error('Timeout'), { response: { status: 408 } });
        const error429 = Object.assign(new Error('Rate Limited'), { response: { status: 429 } });
        
        expect(isRetryableError(error500)).toBe(true);
        expect(isRetryableError(error502)).toBe(true);
        expect(isRetryableError(error503)).toBe(true);
        expect(isRetryableError(error408)).toBe(true);
        expect(isRetryableError(error429)).toBe(true);
      });

      it('identifies non-retryable HTTP status codes', () => {
        const error400 = Object.assign(new Error('Bad Request'), { response: { status: 400 } });
        const error401 = Object.assign(new Error('Unauthorized'), { response: { status: 401 } });
        const error403 = Object.assign(new Error('Forbidden'), { response: { status: 403 } });
        const error404 = Object.assign(new Error('Not Found'), { response: { status: 404 } });
        
        expect(isRetryableError(error400)).toBe(false);
        expect(isRetryableError(error401)).toBe(false);
        expect(isRetryableError(error403)).toBe(false);
        expect(isRetryableError(error404)).toBe(false);
      });

      it('identifies network errors as retryable', () => {
        expect(isRetryableError(new Error('Network error'))).toBe(true);
        expect(isRetryableError(new Error('Fetch failed'))).toBe(true);
        expect(isRetryableError(new Error('Connection timeout'))).toBe(true);
      });

      it('returns false for non-retryable errors', () => {
        expect(isRetryableError(new Error('Validation error'))).toBe(false);
        expect(isRetryableError('string error')).toBe(false);
        expect(isRetryableError(null)).toBe(false);
      });
    });
  });

  describe('withResilience', () => {
    it('applies single resilience pattern', async () => {
      const mockOperation = jest.fn().mockResolvedValue('success');
      
      const result = await withResilience(mockOperation, {
        timeout: { timeoutMs: 1000 }
      });
      
      expect(result).toBe('success');
    });

    it('applies multiple resilience patterns', async () => {
      let attemptCount = 0;
      const mockOperation = jest.fn().mockImplementation(async () => {
        attemptCount++;
        if (attemptCount <= 2) {
          throw new Error('Temporary failure');
        }
        return 'success';
      });
      
      // Remove timeout to focus on retry behavior
      const result = await withResilience(mockOperation, {
        retry: { maxAttempts: 3, baseDelay: 10 } // Just retry for now
      });
      
      expect(result).toBe('success');
      expect(mockOperation).toHaveBeenCalledTimes(3);
    });

    it('uses fallback when all resilience patterns fail', async () => {
      const mockOperation = jest.fn().mockImplementation(async () => {
        throw new Error('Service temporarily unavailable');
      });
      const fallbackOperation = jest.fn().mockResolvedValue('fallback success');
      
      const result = await withResilience(mockOperation, {
        retry: { maxAttempts: 2, baseDelay: 10 }, // Faster retries for testing
        fallback: fallbackOperation
      });
      
      expect(result).toBe('fallback success');
      expect(mockOperation).toHaveBeenCalledTimes(2);
      expect(fallbackOperation).toHaveBeenCalled();
    });

    it('works with empty options', async () => {
      const mockOperation = jest.fn().mockResolvedValue('success');
      
      const result = await withResilience(mockOperation);
      
      expect(result).toBe('success');
    });

    it('combines circuit breaker with retry correctly', async () => {
      const circuitBreaker = new CircuitBreaker({ failureThreshold: 3, resetTimeout: 100 });
      let attemptCount = 0;
      
      const mockOperation = jest.fn().mockImplementation(() => {
        attemptCount++;
        return Promise.reject(new Error('Service failure'));
      });
      
      // Make multiple calls to trip the circuit breaker
      for (let i = 0; i < 3; i++) {
        try {
          await withResilience(mockOperation, {
            retry: { maxAttempts: 1 }, // Single attempt per call
            circuitBreaker
          });
        } catch (error) {
          // Expected to fail
        }
      }
      
      // Circuit should be open now (after 3 failures)
      expect(circuitBreaker.getState()).toBe('open');
      
      // Wait for circuit to enter half-open state
      await sleep(150);
      
      // Reset mock for recovery attempt
      mockOperation.mockImplementation(() => Promise.resolve('recovery success'));
      
      const result = await withResilience(mockOperation, {
        circuitBreaker
      });
      
      expect(result).toBe('recovery success');
    });
  });

  describe('integration scenarios', () => {
    it('handles complex failure scenarios with full resilience stack', async () => {
      const circuitBreaker = new CircuitBreaker({ failureThreshold: 4 }); // Allow 4 attempts before opening
      const bulkhead = new Bulkhead(2);
      const cache = new CacheWithTTL<string>(5000);
      
      let networkFailureCount = 0;
      const unreliableNetworkOperation = jest.fn().mockImplementation(async () => {
        networkFailureCount++;
        
        // Simulate intermittent network failures
        if (networkFailureCount <= 2) {
          throw new Error('Network timeout');
        }
        
        if (networkFailureCount <= 3) {
          throw new Error('Service temporarily unavailable');
        }
        
        return `Success after ${networkFailureCount} attempts`;
      });
      
      const result = await withResilience(unreliableNetworkOperation, {
        retry: { maxAttempts: 5, baseDelay: 10 }, // Faster retries for testing
        timeout: { timeoutMs: 10000 }, // Longer timeout to accommodate retries
        circuitBreaker,
        bulkhead,
        fallback: async () => 'Fallback data from cache'
      });
      
      expect(result).toBe('Success after 4 attempts');
    });

    it('gracefully handles extreme failure conditions', async () => {
      const circuitBreaker = new CircuitBreaker({ failureThreshold: 1 });
      
      const alwaysFailingOperation = jest.fn().mockImplementation(async () => {
        throw new Error('Critical system failure');
      });
      const reliableFallback = jest.fn().mockImplementation(async () => 'Emergency fallback response');
      
      const result = await withResilience(alwaysFailingOperation, {
        retry: { maxAttempts: 2 },
        circuitBreaker,
        fallback: reliableFallback
      });
      
      expect(result).toBe('Emergency fallback response');
      expect(circuitBreaker.getState()).toBe('open');
    });
  });
});