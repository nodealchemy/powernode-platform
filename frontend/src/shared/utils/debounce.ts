// Debounce utility for form validation and search
export function debounce<T extends (...args: any[]) => any>(
  func: T,
  wait: number
): (...args: Parameters<T>) => void {
  let timeout: NodeJS.Timeout;
  
  return (...args: Parameters<T>) => {
    clearTimeout(timeout);
    timeout = setTimeout(() => func(...args), wait);
  };
}

// Async debounce for form validation
export function debounceAsync<T extends (...args: any[]) => Promise<any>>(
  func: T,
  wait: number
): (...args: Parameters<T>) => Promise<ReturnType<T>> {
  let timeout: NodeJS.Timeout;
  let resolvePromise: ((value: any) => void) | null = null;
  let rejectPromise: ((reason?: any) => void) | null = null;
  
  return (...args: Parameters<T>): Promise<ReturnType<T>> => {
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
            rejectPromise(error);
          }
        }
      }, wait);
    });
  };
}