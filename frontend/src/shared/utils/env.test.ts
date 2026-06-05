import { getEnvVar, getAppVersion } from './env';

// setupTests.ts defines a non-configurable `globalThis.import.meta.env` with
// VITE_API_BASE_URL / VITE_AUTO_DETECT_BACKEND / VITE_BEHIND_PROXY. We exercise
// the three branches of getEnvVar by toggling NODE_ENV around synchronous calls
// (restored immediately so nothing else observes the change), and the process
// branches by setting/clearing real keys on process.env.

describe('getEnvVar', () => {
  const ORIGINAL_NODE_ENV = process.env.NODE_ENV;

  afterEach(() => {
    process.env.NODE_ENV = ORIGINAL_NODE_ENV;
    delete process.env.__TEST_CRA_KEY__;
  });

  describe('Jest test environment (NODE_ENV=test)', () => {
    it('reads the cra key from process.env', () => {
      process.env.__TEST_CRA_KEY__ = 'cra-value';
      expect(getEnvVar('IGNORED_VITE_KEY', '__TEST_CRA_KEY__', 'fallback')).toBe('cra-value');
    });

    it('returns the default when the cra key is unset', () => {
      expect(getEnvVar('IGNORED_VITE_KEY', '__ABSENT_CRA__', 'the-default')).toBe('the-default');
    });

    it('does NOT read the Vite import.meta bag in test mode', () => {
      // VITE_API_BASE_URL exists in the import.meta bag, but in test mode we
      // read process.env[craKey] only — so this resolves to the default.
      expect(getEnvVar('VITE_API_BASE_URL', '__ABSENT_CRA__', 'def')).toBe('def');
    });
  });

  describe('Vite runtime (NODE_ENV!=test)', () => {
    it('reads the vite key from import.meta.env', () => {
      process.env.NODE_ENV = 'production';
      expect(getEnvVar('VITE_API_BASE_URL', 'NOPE', 'def')).toBe('http://localhost:3000/api/v1');
    });

    it('falls back to the default when neither vite nor cra key is present in the bag', () => {
      process.env.NODE_ENV = 'production';
      expect(getEnvVar('__ABSENT_VITE__', '__ABSENT_CRA__', 'dv')).toBe('dv');
    });

    it('honours the empty-string default parameter', () => {
      process.env.NODE_ENV = 'production';
      expect(getEnvVar('__ABSENT_VITE__', '__ABSENT_CRA__')).toBe('');
    });
  });
});

describe('getAppVersion', () => {
  const ORIGINAL = process.env.npm_package_version;

  afterEach(() => {
    if (ORIGINAL === undefined) {
      delete process.env.npm_package_version;
    } else {
      process.env.npm_package_version = ORIGINAL;
    }
  });

  it('returns npm_package_version when set (resolved via the cra key in test mode)', () => {
    process.env.npm_package_version = '7.8.9';
    expect(getAppVersion()).toBe('7.8.9');
  });

  it('falls back to the 0.0.1-dev default when no version env var is present', () => {
    delete process.env.npm_package_version;
    expect(getAppVersion()).toBe('0.0.1-dev');
  });

  it('always returns a non-empty string', () => {
    const version = getAppVersion();
    expect(typeof version).toBe('string');
    expect(version.length).toBeGreaterThan(0);
  });
});
