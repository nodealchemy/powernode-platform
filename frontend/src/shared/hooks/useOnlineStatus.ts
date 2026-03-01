import { useState, useEffect, useCallback } from 'react';

interface OnlineStatus {
  isOnline: boolean;
  wasOffline: boolean;
  lastOnlineAt: Date | null;
  lastOfflineAt: Date | null;
}

/**
 * Hook to track browser online/offline status
 *
 * Usage:
 *   const { isOnline, wasOffline } = useOnlineStatus();
 *
 *   // Show reconnection feedback
 *   if (wasOffline && isOnline) {
 *     showNotification('Connection restored');
 *   }
 *
 *   // Show offline banner
 *   if (!isOnline) {
 *     return <OfflineBanner />;
 *   }
 */
export function useOnlineStatus(): OnlineStatus {
  const [isOnline, setIsOnline] = useState<boolean>(() =>
    typeof navigator !== 'undefined' ? navigator.onLine : true
  );
  const [wasOffline, setWasOffline] = useState<boolean>(false);
  const [lastOnlineAt, setLastOnlineAt] = useState<Date | null>(null);
  const [lastOfflineAt, setLastOfflineAt] = useState<Date | null>(null);

  const handleOnline = useCallback(() => {
    setIsOnline(true);
    setLastOnlineAt(new Date());
    // Track that we were offline (for reconnection feedback)
    // This will be cleared after component reads it
  }, []);

  const handleOffline = useCallback(() => {
    setIsOnline(false);
    setWasOffline(true);
    setLastOfflineAt(new Date());
  }, []);

  useEffect(() => {
    // Initial state
    if (typeof navigator !== 'undefined') {
      setIsOnline(navigator.onLine);
    }

    // Add event listeners
    window.addEventListener('online', handleOnline);
    window.addEventListener('offline', handleOffline);

    return () => {
      window.removeEventListener('online', handleOnline);
      window.removeEventListener('offline', handleOffline);
    };
  }, [handleOnline, handleOffline]);

  // Auto-clear wasOffline after reconnection (after a delay to allow UI to show feedback)
  useEffect(() => {
    if (isOnline && wasOffline) {
      const timer = setTimeout(() => {
        setWasOffline(false);
      }, 5000); // Clear after 5 seconds

      return () => clearTimeout(timer);
    }
  }, [isOnline, wasOffline]);

  return {
    isOnline,
    wasOffline,
    lastOnlineAt,
    lastOfflineAt
  };
}

/**
 * Simple version that just returns boolean online status
 */
export function useIsOnline(): boolean {
  const { isOnline } = useOnlineStatus();
  return isOnline;
}

export default useOnlineStatus;
