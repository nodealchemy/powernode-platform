/**
 * The dev-mode API error log must never carry the request body.
 *
 * The response interceptor used to hand the raw AxiosError to console.error.
 * That object carries `config.data` — the serialized REQUEST BODY — so any
 * failing write printed what it was sending. For most endpoints that is noise;
 * for a credential write it is key material in a log, which
 * CryptoMaterialSafety forbids in any form (a dev console is a log).
 */

const mockUse = jest.fn();

jest.mock('axios', () => ({
  __esModule: true,
  default: {
    create: () => ({
      interceptors: {
        request: { use: jest.fn() },
        response: { use: (...args: unknown[]) => mockUse(...args) },
      },
      get: jest.fn(),
      post: jest.fn(),
      put: jest.fn(),
      patch: jest.fn(),
      delete: jest.fn(),
    }),
  },
}));

// The interceptor only reaches the store on a 401; these are here so importing
// the module does not drag the real store in.
jest.mock('@/shared/services/index', () => ({
  store: { getState: jest.fn(), dispatch: jest.fn() },
}));
jest.mock('@/shared/services/slices/authSlice', () => ({
  refreshAccessToken: Object.assign(jest.fn(), { fulfilled: { match: () => false } }),
  clearAuth: jest.fn(),
  stopImpersonation: jest.fn(),
}));

const SECRET = 'sk-ant-must-never-be-logged';

type Rejected = (error: unknown) => Promise<unknown>;

/** The rejection handler the module registered on the response interceptor. */
function responseRejectionHandler(): Rejected {
  // The response interceptor is registered second (the request one first), and
  // its rejection handler is the second argument. Indexed rather than .at(-1):
  // the project's lib target predates Array.prototype.at.
  const calls = mockUse.mock.calls;
  return calls[calls.length - 1][1] as Rejected;
}

function credentialWriteFailure() {
  return {
    message: 'Request failed with status code 422',
    config: {
      url: '/system/nodes/n1/node_instances/i1/claude_code_credential',
      method: 'post',
      // Exactly what axios puts here for a JSON POST.
      data: JSON.stringify({ api_key: SECRET }),
    },
    response: { status: 422, data: { success: false, error: 'api_key is invalid' } },
  };
}

describe('api response interceptor error logging', () => {
  const originalEnv = process.env.NODE_ENV;
  let consoleError: jest.SpyInstance;

  beforeEach(() => {
    jest.resetModules();
    mockUse.mockClear();
    (process.env as Record<string, string>).NODE_ENV = 'development';
    consoleError = jest.spyOn(console, 'error').mockImplementation(() => {});
  });

  afterEach(() => {
    consoleError.mockRestore();
    (process.env as Record<string, string>).NODE_ENV = originalEnv as string;
  });

  it('never logs the request body of a failed write', async () => {
    require('./api');
    const onRejected = responseRejectionHandler();
    const error = credentialWriteFailure();

    await expect(onRejected(error)).rejects.toBe(error);

    expect(consoleError).toHaveBeenCalled();
    const logged = JSON.stringify(consoleError.mock.calls);
    expect(logged).not.toContain(SECRET);
    expect(logged).not.toContain('api_key');
  });

  it('still logs what a developer needs: status, method and url', async () => {
    require('./api');
    const onRejected = responseRejectionHandler();
    const error = credentialWriteFailure();

    await expect(onRejected(error)).rejects.toBe(error);

    expect(consoleError).toHaveBeenCalledWith(
      '[API Error]',
      expect.objectContaining({
        status: 422,
        method: 'post',
        url: '/system/nodes/n1/node_instances/i1/claude_code_credential',
        message: 'Request failed with status code 422',
      }),
    );
  });

  it('logs nothing outside development', async () => {
    (process.env as Record<string, string>).NODE_ENV = 'production';
    require('./api');
    const onRejected = responseRejectionHandler();
    const error = credentialWriteFailure();

    await expect(onRejected(error)).rejects.toBe(error);
    expect(consoleError).not.toHaveBeenCalled();
  });

  it('logs nothing for a request that asked to be silent', async () => {
    require('./api');
    const onRejected = responseRejectionHandler();
    const error = {
      ...credentialWriteFailure(),
      config: { ...credentialWriteFailure().config, silentAuth: true },
    };

    await expect(onRejected(error)).rejects.toBe(error);
    expect(consoleError).not.toHaveBeenCalled();
  });
});
