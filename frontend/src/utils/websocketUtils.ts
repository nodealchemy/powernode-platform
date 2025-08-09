/**
 * Safely sends a message through WebSocket with proper state checking
 */
export const safeWebSocketSend = (ws: WebSocket | null, message: any, maxRetries = 3, retryDelay = 100): Promise<boolean> => {
  return new Promise((resolve) => {
    if (!ws) {
      console.warn('WebSocket is null, cannot send message');
      resolve(false);
      return;
    }

    const attemptSend = (attempt: number) => {
      if (ws.readyState === WebSocket.OPEN) {
        try {
          ws.send(JSON.stringify(message));
          resolve(true);
        } catch (error) {
          console.error('Failed to send WebSocket message:', error);
          resolve(false);
        }
      } else if (ws.readyState === WebSocket.CONNECTING && attempt < maxRetries) {
        // Wait and retry if still connecting
        setTimeout(() => attemptSend(attempt + 1), retryDelay);
      } else {
        console.warn(`WebSocket not ready for sending (state: ${ws.readyState}), attempts: ${attempt}`);
        resolve(false);
      }
    };

    attemptSend(1);
  });
};

/**
 * Creates a WebSocket with improved error handling and connection management
 */
export const createWebSocket = (url: string, protocols?: string | string[]): Promise<WebSocket> => {
  return new Promise((resolve, reject) => {
    try {
      const ws = new WebSocket(url, protocols);
      
      const timeout = setTimeout(() => {
        ws.close();
        reject(new Error('WebSocket connection timeout'));
      }, 10000); // 10 second timeout

      ws.onopen = () => {
        clearTimeout(timeout);
        resolve(ws);
      };

      ws.onerror = (error) => {
        clearTimeout(timeout);
        reject(error);
      };
    } catch (error) {
      reject(error);
    }
  });
};

/**
 * WebSocket ready states as constants
 */
export const WebSocketState = {
  CONNECTING: 0,
  OPEN: 1,
  CLOSING: 2,
  CLOSED: 3
} as const;

/**
 * Waits for WebSocket to reach OPEN state
 */
export const waitForWebSocketOpen = (ws: WebSocket, timeout = 5000): Promise<boolean> => {
  return new Promise((resolve) => {
    if (ws.readyState === WebSocket.OPEN) {
      resolve(true);
      return;
    }

    const timeoutId = setTimeout(() => {
      resolve(false);
    }, timeout);

    const handleOpen = () => {
      clearTimeout(timeoutId);
      ws.removeEventListener('open', handleOpen);
      ws.removeEventListener('error', handleError);
      ws.removeEventListener('close', handleError);
      resolve(true);
    };

    const handleError = () => {
      clearTimeout(timeoutId);
      ws.removeEventListener('open', handleOpen);
      ws.removeEventListener('error', handleError);
      ws.removeEventListener('close', handleError);
      resolve(false);
    };

    ws.addEventListener('open', handleOpen);
    ws.addEventListener('error', handleError);
    ws.addEventListener('close', handleError);
  });
};