jest.mock('@/shared/services/errorHandler', () => {
  const actual = jest.requireActual('@/shared/services/errorHandler');
  return { ...actual, isRecoverableError: jest.fn(), handleApiError: jest.fn() };
});

import { withRetry, createRetryWrapper, retryable } from './retryUtils';
import { handleApiError, isRecoverableError, ErrorCodes } from '@/shared/services/errorHandler';

const mockIsRecoverable = isRecoverableError as jest.Mock;
const mockHandleApiError = handleApiError as jest.Mock;

const apiErr = (over: Record<string, unknown> = {}) => ({ code: 'UNKNOWN', statusCode: undefined, message: 'err', ...over });

// Kick off the (already-running) promise, drive all fake timers + microtasks
// so the internal sleep()s resolve, then return the settled promise.
async function settle<T>(p: Promise<T>): Promise<T> {
  // Observe the rejection (if any) so it isn't flagged unhandled while we drive
  // timers; the caller's await/.rejects still sees the settled promise.
  p.catch(() => {});
  await jest.runAllTimersAsync();
  return p;
}

beforeEach(() => {
  jest.useFakeTimers();
  mockIsRecoverable.mockReset();
  mockHandleApiError.mockReset().mockReturnValue(apiErr());
});

afterEach(() => jest.useRealTimers());

describe('withRetry', () => {
  it('returns success on the first try (attempts: 1)', async () => {
    const op = jest.fn().mockResolvedValue('data');
    const result = await settle(withRetry(op));
    expect(result).toEqual({ success: true, data: 'data', attempts: 1 });
    expect(op).toHaveBeenCalledTimes(1);
  });

  it('retries a recoverable error then succeeds, invoking onRetry(attempt, error, delay)', async () => {
    const op = jest.fn().mockRejectedValueOnce(new Error('net')).mockResolvedValue('ok');
    mockIsRecoverable.mockReturnValue(true);
    mockHandleApiError.mockReturnValue(apiErr({ code: ErrorCodes.NETWORK_ERROR, message: 'net' }));
    const onRetry = jest.fn();

    const result = await settle(withRetry(op, { maxRetries: 3, initialDelay: 10, onRetry }));

    expect(result).toEqual({ success: true, data: 'ok', attempts: 2 });
    expect(op).toHaveBeenCalledTimes(2);
    expect(onRetry).toHaveBeenCalledTimes(1);
    expect(onRetry).toHaveBeenCalledWith(1, expect.objectContaining({ code: ErrorCodes.NETWORK_ERROR }), expect.any(Number));
  });

  it('does not retry a non-recoverable error (attempts: 1)', async () => {
    const op = jest.fn().mockRejectedValue(new Error('fatal'));
    mockIsRecoverable.mockReturnValue(false);
    mockHandleApiError.mockReturnValue(apiErr({ message: 'fatal' }));

    const result = await settle(withRetry(op, { maxRetries: 3 }));

    expect(result.success).toBe(false);
    expect(result.attempts).toBe(1);
    expect(op).toHaveBeenCalledTimes(1);
  });

  it('exhausts maxRetries then fails with attempts = maxRetries + 1', async () => {
    const op = jest.fn().mockRejectedValue(new Error('boom'));
    mockIsRecoverable.mockReturnValue(true);
    mockHandleApiError.mockReturnValue(apiErr({ code: ErrorCodes.SERVICE_UNAVAILABLE }));
    const onRetry = jest.fn();

    const result = await settle(withRetry(op, { maxRetries: 2, initialDelay: 5, onRetry }));

    expect(result.success).toBe(false);
    expect(result.attempts).toBe(3);
    expect(op).toHaveBeenCalledTimes(3);
    expect(onRetry).toHaveBeenCalledTimes(2);
  });
});

describe('createRetryWrapper', () => {
  it('forwards args to the wrapped operation', async () => {
    const op = jest.fn().mockResolvedValue('r');
    const wrapped = createRetryWrapper(op, { maxRetries: 0 });

    const result = await settle(wrapped('a', 'b'));

    expect(result).toEqual({ success: true, data: 'r', attempts: 1 });
    expect(op).toHaveBeenCalledWith('a', 'b');
  });
});

describe('retryable', () => {
  it('returns the value on success', async () => {
    const op = jest.fn().mockResolvedValue('value');
    const wrapped = retryable(op, { maxRetries: 0 });
    await expect(settle(wrapped())).resolves.toBe('value');
  });

  it('re-throws on ultimate failure', async () => {
    const op = jest.fn().mockRejectedValue(new Error('x'));
    mockIsRecoverable.mockReturnValue(false);
    mockHandleApiError.mockReturnValue(apiErr({ message: 'ultimate' }));
    const wrapped = retryable(op, { maxRetries: 0 });
    await expect(settle(wrapped())).rejects.toThrow('ultimate');
  });
});
