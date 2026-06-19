/**
 * WebSocket message type - can be any JSON-serializable value
 */
export type WebSocketMessage = Record<string, unknown> | string | number | boolean | null | unknown[];
