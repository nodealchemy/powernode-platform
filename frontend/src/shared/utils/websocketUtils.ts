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
