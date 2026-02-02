/**
 * WebSocket message type - can be any JSON-serializable value
 */
export type WebSocketMessage = Record<string, unknown> | string | number | boolean | null | unknown[];

/**
 * Safely sends a message through WebSocket with proper state checking
 */
export const safeWebSocketSend = (ws: WebSocket | null, message: WebSocketMessage, maxRetries = 3, retryDelay = 100): Promise<boolean> => {
  return new Promise((resolve) => {
    if (!ws) {
      resolve(false);
      return;
    }

    const attemptSend = (attempt: number) => {
      if (ws.readyState === WebSocket.OPEN) {
        try {
          ws.send(JSON.stringify(message));
          resolve(true);
        } catch {
          resolve(false);
        }
      } else if (ws.readyState === WebSocket.CONNECTING && attempt < maxRetries) {
        // Wait and retry if still connecting
        setTimeout(() => attemptSend(attempt + 1), retryDelay);
      } else {
        resolve(false);
      }
    };

    attemptSend(1);
  });
};
