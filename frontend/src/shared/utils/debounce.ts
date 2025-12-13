/**
 * Debounce utility for form validation and search
 *
 * Creates a debounced version of a function that delays execution
 * until after the specified wait time has elapsed since the last call.
 */
export function debounce<T extends (...args: Parameters<T>) => ReturnType<T>>(
  func: T,
  wait: number
): (...args: Parameters<T>) => void {
  let timeout: NodeJS.Timeout;

  return (...args: Parameters<T>) => {
    clearTimeout(timeout);
    timeout = setTimeout(() => func(...args), wait);
  };
}

/**
 * Async debounce for form validation
 *
 * Creates a debounced version of an async function. Each call returns a promise
 * that resolves with the result of the function after the wait period.
 * Previous pending calls are rejected with an Error('Debounced').
 */
export function debounceAsync<TArgs extends unknown[], TReturn>(
  func: (...args: TArgs) => Promise<TReturn>,
  wait: number
): (...args: TArgs) => Promise<TReturn> {
  let timeout: NodeJS.Timeout;
  let resolvePromise: ((value: TReturn) => void) | null = null;
  let rejectPromise: ((reason?: Error) => void) | null = null;

  return (...args: TArgs): Promise<TReturn> => {
    return new Promise((resolve, reject) => {
      // Clear existing timeout and reject previous promise
      if (timeout) {
        clearTimeout(timeout);
        if (rejectPromise) {
          rejectPromise(new Error('Debounced'));
        }
      }

      resolvePromise = resolve;
      rejectPromise = reject;

      timeout = setTimeout(async () => {
        try {
          const result = await func(...args);
          if (resolvePromise) {
            resolvePromise(result);
          }
        } catch (error) {
          if (rejectPromise) {
            rejectPromise(error instanceof Error ? error : new Error(String(error)));
          }
        }
      }, wait);
    });
  };
}
