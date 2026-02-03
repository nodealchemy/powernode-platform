import { renderHook, act } from '@testing-library/react';
import { useAsyncState, useLoadingState, useAsyncOperations } from './useAsyncState';

describe('useAsyncState', () => {
  describe('useAsyncState hook', () => {
    it('initializes with correct default values', () => {
      const { result } = renderHook(() => useAsyncState<string>());
      
      expect(result.current).toBeTruthy();
      expect(result.current[0].data).toBe(null);
      expect(result.current[0].loading).toBe(false);
      expect(result.current[0].error).toBe(null);
    });

    it('initializes with custom initial data', () => {
      const { result } = renderHook(() => useAsyncState<string>('initial'));
      
      expect(result.current[0].data).toBe('initial');
      expect(result.current[0].loading).toBe(false);
      expect(result.current[0].error).toBe(null);
    });

    it('updates data correctly', () => {
      const { result } = renderHook(() => useAsyncState<string>());
      
      act(() => {
        result.current[1].setData('new data');
      });
      
      expect(result.current[0].data).toBe('new data');
    });

    it('updates loading state correctly', () => {
      const { result } = renderHook(() => useAsyncState<string>());
      
      act(() => {
        result.current[1].setLoading(true);
      });
      
      expect(result.current[0].loading).toBe(true);
    });

    it('updates error state correctly', () => {
      const { result } = renderHook(() => useAsyncState<string>());
      
      act(() => {
        result.current[1].setError('test error');
      });
      
      expect(result.current[0].error).toBe('test error');
    });

    it('resets to initial state', () => {
      const { result } = renderHook(() => useAsyncState<string>('initial'));
      
      // Change state
      act(() => {
        result.current[1].setData('new data');
        result.current[1].setLoading(true);
        result.current[1].setError('test error');
      });
      
      // Reset
      act(() => {
        result.current[1].reset();
      });
      
      expect(result.current[0].data).toBe('initial');
      expect(result.current[0].loading).toBe(false);
      expect(result.current[0].error).toBe(null);
    });

    it('executes async function successfully', async () => {
      const { result } = renderHook(() => useAsyncState<string>());
      
      const asyncFn = jest.fn().mockResolvedValue('success');
      let executeResult: string | null;
      
      await act(async () => {
        executeResult = await result.current[1].execute(asyncFn);
      });
      
      expect(executeResult!).toBe('success');
      expect(result.current[0].data).toBe('success');
      expect(result.current[0].loading).toBe(false);
      expect(result.current[0].error).toBe(null);
      expect(asyncFn).toHaveBeenCalledTimes(1);
    });

    it('handles async function failure', async () => {
      const { result } = renderHook(() => useAsyncState<string>());
      
      const asyncFn = jest.fn().mockRejectedValue(new Error('test error'));
      let executeResult: string | null = null;
      
      await act(async () => {
        executeResult = await result.current[1].execute(asyncFn);
      });
      
      expect(executeResult).toBe(null);
      expect(result.current[0].data).toBe(null);
      expect(result.current[0].loading).toBe(false);
      expect(result.current[0].error).toBe('test error');
    });

    it('handles non-Error failures gracefully', async () => {
      const { result } = renderHook(() => useAsyncState<string>());
      
      const asyncFn = jest.fn().mockRejectedValue('string error');
      let executeResult: string | null = null;
      
      await act(async () => {
        executeResult = await result.current[1].execute(asyncFn);
      });
      
      expect(executeResult).toBe(null);
      expect(result.current[0].error).toBe('An error occurred');
    });

    it('manages loading state during execution', async () => {
      const { result } = renderHook(() => useAsyncState<string>());
      
      let resolvePromise: (value: string) => void;
      const asyncFn = jest.fn().mockImplementation(() => {
        return new Promise<string>((resolve) => {
          resolvePromise = resolve;
        });
      });
      
      // Check initial state
      expect(result.current[0].loading).toBe(false);
      
      // Start execution without waiting
      let executePromise: Promise<string | null>;
      act(() => {
        executePromise = result.current[1].execute(asyncFn);
      });
      
      // Loading should be true immediately after starting
      expect(result.current[0].loading).toBe(true);
      
      // Resolve the promise
      await act(async () => {
        resolvePromise!('result');
        await executePromise!;
      });
      
      // After resolution, loading should be false
      expect(result.current[0].loading).toBe(false);
      expect(result.current[0].data).toBe('result');
    });

    it('clears error when starting new execution', async () => {
      const { result } = renderHook(() => useAsyncState<string>());
      
      const failingFn = jest.fn().mockRejectedValue(new Error('First error'));
      const successFn = jest.fn().mockResolvedValue('success');
      
      // First execution fails
      await act(async () => {
        try {
          await result.current[1].execute(failingFn);
        } catch (_error) {
          // Expected to fail
        }
      });
      
      expect(result.current[0].error).toBe('First error');
      
      // Second execution succeeds
      await act(async () => {
        await result.current[1].execute(successFn);
      });
      
      expect(result.current[0].error).toBe(null);
      expect(result.current[0].data).toBe('success');
    });
  });

  describe('useLoadingState hook', () => {
    it('initializes with correct default values', () => {
      const { result } = renderHook(() => useLoadingState());
      
      expect(result.current).toBeDefined();
      expect(result.current.loading).toBe(false);
      expect(result.current.error).toBe(null);
      expect(typeof result.current.withLoading).toBe('function');
      expect(typeof result.current.reset).toBe('function');
    });

    it('manages loading state during execution', async () => {
      const { result } = renderHook(() => useLoadingState());
      
      const asyncFn = jest.fn().mockResolvedValue('result');
      let executeResult: string | null = null;
      
      await act(async () => {
        executeResult = await result.current.withLoading(asyncFn);
      });
      
      expect(executeResult).toBe('result');
      expect(result.current.loading).toBe(false);
      expect(result.current.error).toBe(null);
    });

    it('handles errors correctly', async () => {
      const { result } = renderHook(() => useLoadingState());
      
      const failingFn = jest.fn().mockRejectedValue(new Error('test error'));
      let executeResult: string | null = null;
      
      await act(async () => {
        executeResult = await result.current.withLoading(failingFn);
      });
      
      expect(executeResult).toBe(null);
      expect(result.current.loading).toBe(false);
      expect(result.current.error).toBe('test error');
    });

    it('resets state correctly', async () => {
      const { result } = renderHook(() => useLoadingState());
      
      // First cause an error
      const failingFn = jest.fn().mockRejectedValue(new Error('test error'));
      await act(async () => {
        await result.current.withLoading(failingFn);
      });
      
      expect(result.current.error).toBe('test error');
      
      // Reset
      act(() => {
        result.current.reset();
      });
      
      expect(result.current.loading).toBe(false);
      expect(result.current.error).toBe(null);
    });

    it('can manually set errors', () => {
      const { result } = renderHook(() => useLoadingState());
      
      act(() => {
        result.current.setError('manual error');
      });
      
      expect(result.current.error).toBe('manual error');
    });
  });

  describe('useAsyncOperations hook', () => {
    it('initializes with empty operations', () => {
      const { result } = renderHook(() => useAsyncOperations());
      
      expect(result.current.operations).toEqual({});
      expect(result.current.isAnyLoading).toBe(false);
      expect(result.current.hasAnyError).toBe(false);
      expect(result.current.allErrors).toEqual([]);
    });

    it('creates operations correctly', () => {
      const { result } = renderHook(() => useAsyncOperations());
      
      act(() => {
        result.current.createOperation('test');
      });
      
      const operation = result.current.getOperation('test');
      expect(operation).toEqual({
        data: null,
        loading: false,
        error: null
      });
    });

    it('executes operations successfully', async () => {
      const { result } = renderHook(() => useAsyncOperations());
      
      const asyncFn = jest.fn().mockResolvedValue('success');
      
      act(() => {
        result.current.createOperation('test');
      });
      
      await act(async () => {
        await result.current.executeOperation('test', asyncFn);
      });
      
      const operation = result.current.getOperation('test');
      expect(operation.data).toBe('success');
      expect(operation.loading).toBe(false);
      expect(operation.error).toBe(null);
    });

    it('handles operation failures', async () => {
      const { result } = renderHook(() => useAsyncOperations());
      
      const failingFn = jest.fn().mockRejectedValue(new Error('test error'));
      
      act(() => {
        result.current.createOperation('test');
      });
      
      await act(async () => {
        await result.current.executeOperation('test', failingFn);
      });
      
      const operation = result.current.getOperation('test');
      expect(operation.data).toBe(null);
      expect(operation.loading).toBe(false);
      expect(operation.error).toBe('test error');
    });

    it('resets operations correctly', () => {
      const { result } = renderHook(() => useAsyncOperations());
      
      act(() => {
        result.current.createOperation('test');
      });
      
      // Set some data
      act(() => {
        result.current.operations.test = { data: 'test', loading: true, error: 'error' };
      });
      
      act(() => {
        result.current.resetOperation('test');
      });
      
      const operation = result.current.getOperation('test');
      expect(operation).toEqual({
        data: null,
        loading: false,
        error: null
      });
    });

    it('tracks loading state across operations', async () => {
      const { result } = renderHook(() => useAsyncOperations());
      
      let resolvePromise: (value: string) => void;
      const asyncFn = jest.fn().mockImplementation(() => {
        return new Promise<string>((resolve) => {
          resolvePromise = resolve;
        });
      });
      
      act(() => {
        result.current.createOperation('test');
      });
      
      // Start execution and use act to flush state updates
      let executePromise: Promise<any>;
      act(() => {
        executePromise = result.current.executeOperation('test', asyncFn);
      });
      
      // Check loading state after state update is flushed
      expect(result.current.isAnyLoading).toBe(true);
      
      // Resolve the promise and wait for completion  
      await act(async () => {
        resolvePromise!('result');
        await executePromise!;
      });
      
      // Should no longer be loading
      expect(result.current.isAnyLoading).toBe(false);
    });

    it('tracks errors across operations', async () => {
      const { result } = renderHook(() => useAsyncOperations());
      
      const failingFn1 = jest.fn().mockRejectedValue(new Error('Error 1'));
      const failingFn2 = jest.fn().mockRejectedValue(new Error('Error 2'));
      const successFn = jest.fn().mockResolvedValue('success');
      
      act(() => {
        result.current.createOperation('op1');
        result.current.createOperation('op2');
        result.current.createOperation('op3');
      });
      
      // Execute operations and wait for them to complete within act()
      await act(async () => {
        await result.current.executeOperation('op1', failingFn1);
        await result.current.executeOperation('op2', failingFn2);
        await result.current.executeOperation('op3', successFn);
      });
      
      expect(result.current.hasAnyError).toBe(true);
      expect(result.current.allErrors).toEqual([
        { key: 'op1', error: 'Error 1' },
        { key: 'op2', error: 'Error 2' }
      ]);
    });

    it('returns default state for non-existent operations', () => {
      const { result } = renderHook(() => useAsyncOperations());
      
      const operation = result.current.getOperation('non-existent');
      expect(operation).toEqual({
        data: null,
        loading: false,
        error: null
      });
    });
  });

  describe('integration scenarios', () => {
    it('handles rapid state changes correctly', () => {
      const { result } = renderHook(() => useAsyncState<number>());
      
      // Check that hook returns a tuple
      expect(result.current).toBeDefined();
      expect(Array.isArray(result.current)).toBe(true);
      expect(result.current.length).toBe(2);
      
      // Rapid updates
      act(() => {
        result.current[1].setData(1);
        result.current[1].setData(2);
        result.current[1].setData(3);
      });
      
      expect(result.current[0].data).toBe(3);
    });

    it('maintains referential stability of actions', () => {
      const { result, rerender } = renderHook(() => useAsyncState<string>('initial'));
      
      // Check that hook returns properly
      expect(result.current).toBeDefined();
      expect(Array.isArray(result.current)).toBe(true);
      
      const firstActions = result.current[1];
      
      // Trigger re-render
      rerender();
      
      const secondActions = result.current[1];
      
      // Actions should be referentially stable
      expect(firstActions.setData).toBe(secondActions.setData);
      expect(firstActions.setLoading).toBe(secondActions.setLoading);
      expect(firstActions.setError).toBe(secondActions.setError);
      expect(firstActions.reset).toBe(secondActions.reset);
      expect(firstActions.execute).toBe(secondActions.execute);
    });
  });
});