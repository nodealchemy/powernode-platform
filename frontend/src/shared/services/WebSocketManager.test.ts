import { wsManager } from './WebSocketManager';

// N2: reason: 'unauthorized' is treated as an expired session and silently
// refreshed + reconnected — correct for a real token expiry, but exactly
// wrong for a maintenance-mode disconnect (refresh itself is never gated,
// so it succeeds immediately and the new connection gets rejected again,
// looping roughly once a second for as long as maintenance stays on). These
// tests exercise the REAL WebSocketManager singleton (not a mock) against a
// fake WebSocket global, since the reconnect-storm bug lives inside its own
// #connect()/#handleMessage logic — a mocked wsManager (as every OTHER
// consumer test uses) can't see this class of regression at all.
class FakeWebSocket {
  static instances: FakeWebSocket[] = [];
  static OPEN = 1;
  static CONNECTING = 0;

  readyState = FakeWebSocket.CONNECTING;
  onopen: (() => void) | null = null;
  onmessage: ((event: { data: string }) => void) | null = null;
  onclose: ((event: { code: number; reason: string }) => void) | null = null;
  onerror: ((event: unknown) => void) | null = null;

  constructor(public url: string) {
    FakeWebSocket.instances.push(this);
  }

  close(_code?: number, _reason?: string): void {
    this.readyState = 3; // CLOSED
  }

  // Test helper — not part of the real WebSocket API
  simulateOpen(): void {
    this.readyState = FakeWebSocket.OPEN;
    this.onopen?.();
  }

  simulateMessage(data: unknown): void {
    this.onmessage?.({ data: JSON.stringify(data) });
  }
}

describe('WebSocketManager', () => {
  const getUrl = () => 'ws://localhost/cable?token=test';

  beforeEach(() => {
    jest.useFakeTimers();
    FakeWebSocket.instances = [];
    (global as unknown as { WebSocket: typeof FakeWebSocket }).WebSocket = FakeWebSocket;
    // Clean slate: disconnect() doesn't touch the maintenance-mode guard
    // (deliberately — see WebSocketManager#setMaintenanceActive), so it's
    // reset explicitly.
    wsManager.disconnect();
    wsManager.setMaintenanceActive(false);
  });

  afterEach(() => {
    wsManager.disconnect();
    wsManager.setMaintenanceActive(false);
    jest.useRealTimers();
  });

  function connectAndOpen(config: Parameters<typeof wsManager.initialize>[0]) {
    wsManager.initialize(config);
    jest.advanceTimersByTime(200); // clears the connect debounce
    const socket = FakeWebSocket.instances[FakeWebSocket.instances.length - 1];
    socket.simulateOpen();
    return socket;
  }

  it('sets the maintenance flag and does not immediately reconnect on a maintenance_mode disconnect', () => {
    const onMaintenanceMode = jest.fn();
    const socket = connectAndOpen({ getUrl, onMaintenanceMode });

    socket.simulateMessage({ type: 'disconnect', reason: 'maintenance_mode', message: 'Upgrading', estimated_completion: '30 minutes' });

    expect(onMaintenanceMode).toHaveBeenCalledWith('Upgrading', '30 minutes');
    expect(wsManager.getMaintenanceActive()).toBe(true);

    const countBefore = FakeWebSocket.instances.length;
    jest.advanceTimersByTime(30000); // well past any backoff window
    expect(FakeWebSocket.instances.length).toBe(countBefore); // no new socket opened
  });

  it('does NOT auto-reconnect on the close event that follows a maintenance_mode disconnect', () => {
    const socket = connectAndOpen({ getUrl });

    socket.simulateMessage({ type: 'disconnect', reason: 'maintenance_mode' });
    // The real close event that follows the server closing the socket.
    socket.onclose?.({ code: 1000, reason: 'maintenance_mode' });

    const countBefore = FakeWebSocket.instances.length;
    jest.advanceTimersByTime(30000);
    expect(FakeWebSocket.instances.length).toBe(countBefore);
  });

  it('resumes connecting once setMaintenanceActive(false) is called', () => {
    const socket = connectAndOpen({ getUrl });
    socket.simulateMessage({ type: 'disconnect', reason: 'maintenance_mode' });
    expect(wsManager.getMaintenanceActive()).toBe(true);

    wsManager.setMaintenanceActive(false);
    wsManager.reconnect();
    jest.advanceTimersByTime(2000); // clears both the debounce and any backoff window

    expect(FakeWebSocket.instances.length).toBeGreaterThan(1);
  });

  it('still refreshes and reconnects on an "unauthorized" disconnect (unaffected by the maintenance_mode branch)', () => {
    const socket = connectAndOpen({ getUrl });

    socket.simulateMessage({ type: 'disconnect', reason: 'unauthorized' });

    expect(wsManager.getMaintenanceActive()).toBe(false);
  });
});
