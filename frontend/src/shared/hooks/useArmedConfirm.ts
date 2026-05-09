import { useCallback, useEffect, useRef, useState } from 'react';

interface UseArmedConfirmOptions {
  /** Window in ms during which the second click commits. Defaults to 5000. */
  armWindowMs?: number;
  /** Optional callback fired when the arm window expires without confirmation. */
  onTimeout?: () => void;
}

interface UseArmedConfirmReturn {
  /** True after the first click; flips back to false on confirm/timeout/reset. */
  armed: boolean;
  /** Call on click. First call arms, second call within the window commits. */
  trigger: () => void;
  /** Force-disarm (e.g., when the parent modal/menu closes). */
  reset: () => void;
}

/**
 * Two-stage confirmation hook for destructive frontend actions. Per platform
 * convention (memory `feedback_destructive_confirm`), single-click delete/
 * reject/terminate buttons cause data loss from mis-clicks; arm-and-confirm
 * gives the user a brief "did I really mean that?" window without the weight
 * of a modal.
 *
 * Usage:
 *   const { armed, trigger } = useArmedConfirm(handleDelete);
 *   <Button variant={armed ? 'danger' : 'secondary'} onClick={trigger}>
 *     {armed ? 'Click to confirm' : 'Delete'}
 *   </Button>
 */
export function useArmedConfirm(
  onConfirm: () => void | Promise<void>,
  options: UseArmedConfirmOptions = {}
): UseArmedConfirmReturn {
  const { armWindowMs = 5000, onTimeout } = options;
  const [armed, setArmed] = useState(false);
  const timerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const onConfirmRef = useRef(onConfirm);
  const onTimeoutRef = useRef(onTimeout);

  onConfirmRef.current = onConfirm;
  onTimeoutRef.current = onTimeout;

  const reset = useCallback(() => {
    setArmed(false);
    if (timerRef.current) {
      clearTimeout(timerRef.current);
      timerRef.current = null;
    }
  }, []);

  const trigger = useCallback(() => {
    if (armed) {
      if (timerRef.current) {
        clearTimeout(timerRef.current);
        timerRef.current = null;
      }
      setArmed(false);
      void onConfirmRef.current();
      return;
    }
    setArmed(true);
    timerRef.current = setTimeout(() => {
      setArmed(false);
      timerRef.current = null;
      onTimeoutRef.current?.();
    }, armWindowMs);
  }, [armed, armWindowMs]);

  useEffect(() => {
    return () => {
      if (timerRef.current) clearTimeout(timerRef.current);
    };
  }, []);

  return { armed, trigger, reset };
}
