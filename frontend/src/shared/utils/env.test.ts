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
  // The version comes ONLY from the __BUILD_INFO__ define (vite.config.ts,
  // fed by POWERNODE_BUILD_INFO_JSON / the checkout's git tags). The old
  // VITE_APP_VERSION / npm_package_version env vars are not read.
  const g = globalThis as unknown as { __BUILD_INFO__?: unknown };
  const ORIGINAL_BUILD_INFO = g.__BUILD_INFO__;
  const ORIGINAL_NPM = process.env.npm_package_version;

  afterEach(() => {
    if (ORIGINAL_BUILD_INFO === undefined) {
      delete g.__BUILD_INFO__;
    } else {
      g.__BUILD_INFO__ = ORIGINAL_BUILD_INFO;
    }
    if (ORIGINAL_NPM === undefined) {
      delete process.env.npm_package_version;
    } else {
      process.env.npm_package_version = ORIGINAL_NPM;
    }
  });

  it('returns the __BUILD_INFO__ version when the define exists', () => {
    g.__BUILD_INFO__ = { version: '0.3.0-dev.12+abc1234', sha: null, short_sha: 'abc1234', branch: 'develop', tag: null, release: false, built_at: null, source: 'git' };
    expect(getAppVersion()).toBe('0.3.0-dev.12+abc1234');
  });

  it('falls back to the 0.0.0-dev default when there is no build info', () => {
    delete g.__BUILD_INFO__;
    expect(getAppVersion()).toBe('0.0.0-dev');
  });

  it('ignores npm_package_version (package.json is only written by release.sh)', () => {
    delete g.__BUILD_INFO__;
    process.env.npm_package_version = '7.8.9';
    expect(getAppVersion()).toBe('0.0.0-dev');
  });
});
