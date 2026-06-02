/**
 * Form submission hooks for consistent form handling
 */

import { useCallback, useRef,useState } from 'react';
import { useDispatch } from 'react-redux';

import type { AppDispatch } from '@/shared/services';
import { addNotification } from '@/shared/services/slices/uiSlice';
import { getErrorMessage } from '@/shared/utils/errorHandling';


// Submission state interface
export interface SubmissionState<T = unknown> {
  isSubmitting: boolean;
  isSuccess: boolean;
  isError: boolean;
  error: string | null;
  data: T | null;
}

// Submission options
export interface SubmissionOptions<T, R> {
  onSuccess?: (data: R) => void | Promise<void>;
  onError?: (error: string, fieldErrors?: Record<string, string>) => void;
  successMessage?: string;
  errorMessage?: string;
  resetOnSuccess?: boolean;
  preventDefault?: boolean;
  validateBeforeSubmit?: () => boolean | Promise<boolean>;
  transformData?: (data: T) => unknown;
  extractFieldErrors?: (error: unknown) => Record<string, string> | null;
}

/**
 * Hook for handling form submissions with consistent error handling and notifications
 */
export function useFormSubmission<T = unknown, R = unknown>(
  submitFn: (data: T) => Promise<R>,
  options: SubmissionOptions<T, R> = {}
) {
  const dispatch = useDispatch<AppDispatch>();
  const [state, setState] = useState<SubmissionState<R>>({
    isSubmitting: false,
    isSuccess: false,
    isError: false,
    error: null,
    data: null
  });

  const abortControllerRef = useRef<AbortController | null>(null);

  const {
    onSuccess,
    onError,
    successMessage,
    errorMessage,
    resetOnSuccess = false,
    preventDefault = true,
    validateBeforeSubmit,
    transformData,
    extractFieldErrors
  } = options;

  const handleSubmit = useCallback(async (
    data: T,
    event?: React.FormEvent
  ): Promise<R | null> => {
    // Prevent default form submission
    if (event && preventDefault) {
      event.preventDefault();
    }

    // Run pre-submit validation
    if (validateBeforeSubmit) {
      const isValid = await validateBeforeSubmit();
      if (!isValid) {
        return null;
      }
    }

    // Cancel any pending submission
    if (abortControllerRef.current) {
      abortControllerRef.current.abort();
    }

    // Create new abort controller
    abortControllerRef.current = new AbortController();

    setState({
      isSubmitting: true,
      isSuccess: false,
      isError: false,
      error: null,
      data: null
    });

    try {
      // Transform data if needed
      const submitData = (transformData ? transformData(data) : data) as T;

      // Submit form
      const result = await submitFn(submitData);

      // Check if request was aborted
      if (abortControllerRef.current?.signal.aborted) {
        return null;
      }

      setState({
        isSubmitting: false,
        isSuccess: true,
        isError: false,
        error: null,
        data: result
      });

      // Show success notification
      if (successMessage) {
        dispatch(addNotification({
          type: 'success',
          message: successMessage
        }));
      }

      // Call success callback
      if (onSuccess) {
        await onSuccess(result);
      }

      // Reset form if requested
      if (resetOnSuccess) {
        setState({
          isSubmitting: false,
          isSuccess: false,
          isError: false,
          error: null,
          data: null
        });
      }

      return result;
    } catch (error) {
      // Check if request was aborted
      if (abortControllerRef.current?.signal.aborted) {
        return null;
      }

      const errorMsg = getErrorMessage(error) || errorMessage || 'An error occurred';

      // Extract field-specific errors
      let fieldErrors: Record<string, string> | null = null;
      if (extractFieldErrors) {
        fieldErrors = extractFieldErrors(error);
      } else {
        // Default field error extraction
        if (error && typeof error === 'object' && 'response' in error) {
          const response = (error as Record<string, unknown>).response;
          if (response && typeof response === 'object' && 'data' in response) {
            const data = response.data;
            if (data && typeof data === 'object' && 'errors' in data) {
              const errors = (data as Record<string, unknown>).errors;
              if (errors && typeof errors === 'object') {
                fieldErrors = {};
                Object.entries(errors).forEach(([field, messages]) => {
                  if (Array.isArray(messages) && messages.length > 0) {
                    fieldErrors![field] = messages[0];
                  }
                });
              }
            }
          }
        }
      }

      setState({
        isSubmitting: false,
        isSuccess: false,
        isError: true,
        error: errorMsg,
        data: null
      });

      // Show error notification
      dispatch(addNotification({
        type: 'error',
        message: errorMsg
      }));

      // Call error callback
      if (onError) {
        onError(errorMsg, fieldErrors || undefined);
      }

      return null;
    } finally {
      abortControllerRef.current = null;
    }
  }, [
    submitFn,
    dispatch,
    onSuccess,
    onError,
    successMessage,
    errorMessage,
    resetOnSuccess,
    preventDefault,
    validateBeforeSubmit,
    transformData,
    extractFieldErrors
  ]);

  const reset = useCallback(() => {
    setState({
      isSubmitting: false,
      isSuccess: false,
      isError: false,
      error: null,
      data: null
    });
  }, []);

  const cancel = useCallback(() => {
    if (abortControllerRef.current) {
      abortControllerRef.current.abort();
      abortControllerRef.current = null;
    }
    reset();
  }, [reset]);

  return {
    ...state,
    handleSubmit,
    reset,
    cancel
  };
}
