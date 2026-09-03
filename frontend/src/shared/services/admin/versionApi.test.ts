import { versionApi, VersionInfo, FullVersionInfo, HealthInfo } from './versionApi';

// =============================================================================
// Mocks
//
// versionApi uses `api` from @/shared/services/api for HTTP calls and
// isErrorWithResponse / getErrorMessage from @/shared/utils/errorHandling for
// error normalisation. The api instance is mocked so we never hit the network.
// errorHandling is real — its behaviour is tested indirectly via the catch
// branches in each API method.
// =============================================================================

const mockGet = jest.fn();

jest.mock('@/shared/services/api', () => ({
  api: {
    get: (...args: unknown[]) => mockGet(...args),
  },
}));

// =============================================================================
// Helpers
// =============================================================================

/**
 * Wraps a payload in the AxiosResponse-shaped envelope that the real `api.get`
 * resolves to. The outer `data` key is the Axios `response.data`; inside that
 * sits the Rails double-envelope `{ success, data }`.
 */
function envelope<T>(payload: T) {
  return { data: { success: true, data: payload } };
}

// =============================================================================
// Fixtures
// =============================================================================

const VERSION_INFO: VersionInfo = {
  version: '1.2.3',
  major: 1,
  minor: 2,
  patch: 3,
  build_date: '2026-01-15T10:00:00Z',
  git_commit: 'abc1234',
};

const FULL_VERSION_INFO: FullVersionInfo = {
  version: '1.2.3',
  major: 1,
  minor: 2,
  patch: 3,
  build_date: '2026-01-15T10:00:00Z',
  git_commit: 'abc1234',
  git_branch: 'main',
  rails_version: '8.0.0',
  ruby_version: '3.3.0',
  environment: 'production',
};

const HEALTH_INFO: HealthInfo = {
  status: 'ok',
  version: '1.2.3',
  timestamp: '2026-01-15T10:00:00Z',
  uptime: {
    boot_time: '2026-01-14T08:00:00Z',
    uptime_seconds: 93600,
    uptime_human: '1 day, 2 hours',
  },
};

// =============================================================================
// Tests
// =============================================================================

describe('versionApi', () => {
  beforeEach(() => {
    mockGet.mockReset();
  });

  // ---------------------------------------------------------------------------
  // getVersion
  // ---------------------------------------------------------------------------

  describe('getVersion', () => {
    it('resolves with success response when the API call succeeds', async () => {
      mockGet.mockResolvedValue(envelope(VERSION_INFO));

      const result = await versionApi.getVersion();

      expect(mockGet).toHaveBeenCalledWith('/version');
      expect(result.success).toBe(true);
      expect(result.data).toEqual(VERSION_INFO);
    });

    it('returns the full response.data from the Axios envelope', async () => {
      const body = { success: true, data: VERSION_INFO };
      mockGet.mockResolvedValue({ data: body });

      const result = await versionApi.getVersion();

      expect(result).toEqual(body);
    });

    it('returns a failure response with server error message when the API returns an error response', async () => {
      const apiError = {
        response: { data: { error: 'Version service unavailable' } },
        message: 'Request failed with status code 503',
      };
      mockGet.mockRejectedValue(apiError);

      const result = await versionApi.getVersion();

      expect(result.success).toBe(false);
      expect(result.error).toBe('Version service unavailable');
    });

    it('falls back to the default error message when server response has no error field', async () => {
      const apiError = {
        response: { data: {} },
        message: 'Server Error',
      };
      mockGet.mockRejectedValue(apiError);

      const result = await versionApi.getVersion();

      expect(result.success).toBe(false);
      expect(result.error).toBe('Version service unavailable');
    });

    it('uses getErrorMessage for non-response errors (e.g. network failure)', async () => {
      mockGet.mockRejectedValue(new Error('Network Error'));

      const result = await versionApi.getVersion();

      expect(result.success).toBe(false);
      expect(result.error).toBe('Network Error');
    });

    it('returns an empty VersionInfo object as data on failure', async () => {
      mockGet.mockRejectedValue(new Error('timeout'));

      const result = await versionApi.getVersion();

      expect(result.data).toEqual({});
    });
  });

  // ---------------------------------------------------------------------------
  // getFullVersion
  // ---------------------------------------------------------------------------

  describe('getFullVersion', () => {
    it('resolves with success response when the API call succeeds', async () => {
      mockGet.mockResolvedValue(envelope(FULL_VERSION_INFO));

      const result = await versionApi.getFullVersion();

      expect(mockGet).toHaveBeenCalledWith('/version/full');
      expect(result.success).toBe(true);
      expect(result.data).toEqual(FULL_VERSION_INFO);
    });

    it('returns a failure response with server error message on error response', async () => {
      const apiError = {
        response: { data: { error: 'Unauthorized' } },
        message: 'Request failed with status code 401',
      };
      mockGet.mockRejectedValue(apiError);

      const result = await versionApi.getFullVersion();

      expect(result.success).toBe(false);
      expect(result.error).toBe('Unauthorized');
    });

    it('falls back to "Full version service unavailable" when no server error field', async () => {
      const apiError = {
        response: { data: {} },
        message: 'Server Error',
      };
      mockGet.mockRejectedValue(apiError);

      const result = await versionApi.getFullVersion();

      expect(result.success).toBe(false);
      expect(result.error).toBe('Full version service unavailable');
    });

    it('uses getErrorMessage for non-response errors', async () => {
      mockGet.mockRejectedValue(new Error('Connection refused'));

      const result = await versionApi.getFullVersion();

      expect(result.success).toBe(false);
      expect(result.error).toBe('Connection refused');
    });

    it('returns an empty FullVersionInfo object as data on failure', async () => {
      mockGet.mockRejectedValue(new Error('timeout'));

      const result = await versionApi.getFullVersion();

      expect(result.data).toEqual({});
    });
  });

  // ---------------------------------------------------------------------------
  // getHealth
  // ---------------------------------------------------------------------------

  describe('getHealth', () => {
    it('resolves with success response when the API call succeeds', async () => {
      mockGet.mockResolvedValue(envelope(HEALTH_INFO));

      const result = await versionApi.getHealth();

      expect(mockGet).toHaveBeenCalledWith('/version/health');
      expect(result.success).toBe(true);
      expect(result.data).toEqual(HEALTH_INFO);
    });

    it('returns a failure response with server error message on error response', async () => {
      const apiError = {
        response: { data: { error: 'Service degraded' } },
        message: 'Request failed with status code 500',
      };
      mockGet.mockRejectedValue(apiError);

      const result = await versionApi.getHealth();

      expect(result.success).toBe(false);
      expect(result.error).toBe('Service degraded');
    });

    it('falls back to "Health service unavailable" when no server error field', async () => {
      const apiError = {
        response: { data: {} },
        message: 'Server Error',
      };
      mockGet.mockRejectedValue(apiError);

      const result = await versionApi.getHealth();

      expect(result.success).toBe(false);
      expect(result.error).toBe('Health service unavailable');
    });

    it('uses getErrorMessage for non-response errors', async () => {
      mockGet.mockRejectedValue(new Error('ECONNREFUSED'));

      const result = await versionApi.getHealth();

      expect(result.success).toBe(false);
      expect(result.error).toBe('ECONNREFUSED');
    });

    it('returns an empty HealthInfo object as data on failure', async () => {
      mockGet.mockRejectedValue(new Error('timeout'));

      const result = await versionApi.getHealth();

      expect(result.data).toEqual({});
    });

    it('preserves full uptime shape from a successful response', async () => {
      mockGet.mockResolvedValue(envelope(HEALTH_INFO));

      const result = await versionApi.getHealth();

      expect(result.data.uptime.uptime_seconds).toBe(93600);
      expect(result.data.uptime.uptime_human).toBe('1 day, 2 hours');
      expect(result.data.uptime.boot_time).toBe('2026-01-14T08:00:00Z');
    });
  });

  // ---------------------------------------------------------------------------
  // getFrontendVersion
  // ---------------------------------------------------------------------------

  describe('getFrontendVersion', () => {
    // getFrontendVersion now delegates to the shared getAppVersion() util. In
    // the Jest environment that reads process.env.npm_package_version (the
    // craKey), falling back to the dev default — so we control that env var.
    const ORIGINAL_NPM_VERSION = process.env.npm_package_version;

    afterEach(() => {
      if (ORIGINAL_NPM_VERSION === undefined) {
        delete process.env.npm_package_version;
      } else {
        process.env.npm_package_version = ORIGINAL_NPM_VERSION;
      }
    });

    it('returns "0.0.1-dev" when no version env var is present', () => {
      delete process.env.npm_package_version;
      expect(versionApi.getFrontendVersion()).toBe('0.0.1-dev');
    });

    it('reads npm_package_version when present in the environment', () => {
      process.env.npm_package_version = '5.6.7';
      expect(versionApi.getFrontendVersion()).toBe('5.6.7');
    });

    it('always returns a non-empty string', () => {
      const version = versionApi.getFrontendVersion();
      expect(typeof version).toBe('string');
      expect(version.length).toBeGreaterThan(0);
    });
  });

  // ---------------------------------------------------------------------------
  // displayVersion — release → X.Y.Z, incremental → short sha, unknown → X.Y.Z-dev
  // ---------------------------------------------------------------------------

  describe('displayVersion', () => {
    it('returns the version for a release build', () => {
      expect(versionApi.displayVersion({ version: '1.2.3', short_sha: 'abcdef0', release: true })).toBe('1.2.3');
    });

    it('returns the short sha for an incremental build', () => {
      expect(versionApi.displayVersion({ version: '1.2.3', short_sha: 'abcdef0', release: false })).toBe('abcdef0');
    });

    it('prefers a server-provided display string when present', () => {
      expect(versionApi.displayVersion({ version: '1.2.3', display: 'fedcba9', short_sha: 'abcdef0', release: false })).toBe('fedcba9');
    });

    it('returns <version>-dev when no sha is known', () => {
      expect(versionApi.displayVersion({ version: '1.2.3', short_sha: null, release: false })).toBe('1.2.3-dev');
      expect(versionApi.displayVersion({ version: '1.2.3' })).toBe('1.2.3-dev');
    });

    it('does not double the -dev suffix on a prerelease version', () => {
      expect(versionApi.displayVersion({ version: '0.0.1-dev' })).toBe('0.0.1-dev');
    });
  });

  describe('getFrontendBuildInfo', () => {
    it('falls back to the app version with no identity when no __BUILD_INFO__ define exists', () => {
      const info = versionApi.getFrontendBuildInfo();
      expect(info.version).toBe(versionApi.getFrontendVersion());
      expect(info.release).toBe(false);
      expect(info.short_sha).toBeNull();
      expect(info.source).toBe('local');
    });
  });

  // ---------------------------------------------------------------------------
  // formatVersion
  // ---------------------------------------------------------------------------

  describe('formatVersion', () => {
    it('returns the version string unchanged when showPrerelease is true (default)', () => {
      expect(versionApi.formatVersion('1.2.3-beta.1')).toBe('1.2.3-beta.1');
    });

    it('returns the version string unchanged for a stable version with default showPrerelease', () => {
      expect(versionApi.formatVersion('1.2.3')).toBe('1.2.3');
    });

    it('strips the prerelease segment when showPrerelease is false', () => {
      expect(versionApi.formatVersion('1.2.3-beta.1', false)).toBe('1.2.3');
    });

    it('strips a dev prerelease when showPrerelease is false', () => {
      expect(versionApi.formatVersion('2.0.0-dev', false)).toBe('2.0.0');
    });

    it('strips an alpha prerelease when showPrerelease is false', () => {
      expect(versionApi.formatVersion('0.1.0-alpha.3', false)).toBe('0.1.0');
    });

    it('returns the stable version unchanged when showPrerelease is false and there is no prerelease segment', () => {
      expect(versionApi.formatVersion('3.0.0', false)).toBe('3.0.0');
    });

    it('preserves the full version when showPrerelease is explicitly true', () => {
      expect(versionApi.formatVersion('1.0.0-rc.1', true)).toBe('1.0.0-rc.1');
    });
  });

  // ---------------------------------------------------------------------------
  // parseVersion
  // ---------------------------------------------------------------------------

  describe('parseVersion', () => {
    it('parses a standard semver string into its numeric components', () => {
      const result = versionApi.parseVersion('1.2.3');
      expect(result).toEqual({ major: 1, minor: 2, patch: 3, prerelease: null, full: '1.2.3' });
    });

    it('parses a version with prerelease segment', () => {
      const result = versionApi.parseVersion('2.0.0-beta.1');
      expect(result).toEqual({ major: 2, minor: 0, patch: 0, prerelease: 'beta.1', full: '2.0.0-beta.1' });
    });

    it('defaults to 0 for missing minor/patch segments', () => {
      const result = versionApi.parseVersion('1');
      expect(result.major).toBe(1);
      expect(result.minor).toBe(0);
      expect(result.patch).toBe(0);
    });

    it('sets prerelease to null when absent', () => {
      const result = versionApi.parseVersion('1.0.0');
      expect(result.prerelease).toBeNull();
    });

    it('preserves the full original version string in the full field', () => {
      const full = '3.1.4-rc.2';
      const result = versionApi.parseVersion(full);
      expect(result.full).toBe(full);
    });

    it('parses a dev prerelease tag correctly', () => {
      const result = versionApi.parseVersion('0.9.0-dev');
      expect(result.prerelease).toBe('dev');
    });
  });

  // ---------------------------------------------------------------------------
  // compareVersions
  // ---------------------------------------------------------------------------

  describe('compareVersions', () => {
    it('returns 0 for two identical stable versions', () => {
      expect(versionApi.compareVersions('1.2.3', '1.2.3')).toBe(0);
    });

    it('returns positive when version1 major is greater', () => {
      expect(versionApi.compareVersions('2.0.0', '1.9.9')).toBeGreaterThan(0);
    });

    it('returns negative when version1 major is smaller', () => {
      expect(versionApi.compareVersions('1.0.0', '2.0.0')).toBeLessThan(0);
    });

    it('returns positive when version1 minor is greater (same major)', () => {
      expect(versionApi.compareVersions('1.3.0', '1.2.9')).toBeGreaterThan(0);
    });

    it('returns negative when version1 minor is smaller (same major)', () => {
      expect(versionApi.compareVersions('1.1.0', '1.2.0')).toBeLessThan(0);
    });

    it('returns positive when version1 patch is greater (same major.minor)', () => {
      expect(versionApi.compareVersions('1.2.5', '1.2.4')).toBeGreaterThan(0);
    });

    it('returns negative when version1 patch is smaller (same major.minor)', () => {
      expect(versionApi.compareVersions('1.2.3', '1.2.4')).toBeLessThan(0);
    });

    it('returns 1 when version1 is stable and version2 has a prerelease (stable wins)', () => {
      expect(versionApi.compareVersions('1.0.0', '1.0.0-beta')).toBe(1);
    });

    it('returns -1 when version1 has a prerelease and version2 is stable (prerelease loses)', () => {
      expect(versionApi.compareVersions('1.0.0-alpha', '1.0.0')).toBe(-1);
    });

    it('uses localeCompare when both versions have a prerelease segment', () => {
      // 'alpha' < 'beta' alphabetically
      expect(versionApi.compareVersions('1.0.0-alpha', '1.0.0-beta')).toBeLessThan(0);
      expect(versionApi.compareVersions('1.0.0-beta', '1.0.0-alpha')).toBeGreaterThan(0);
    });

    it('returns 0 for two identical prerelease versions', () => {
      expect(versionApi.compareVersions('1.0.0-rc.1', '1.0.0-rc.1')).toBe(0);
    });
  });

  // ---------------------------------------------------------------------------
  // getVersionBadgeColor
  // ---------------------------------------------------------------------------

  describe('getVersionBadgeColor', () => {
    it('returns success theme classes for a stable release', () => {
      const color = versionApi.getVersionBadgeColor('1.0.0');
      expect(color).toBe('bg-theme-success-bg text-theme-success-fg');
    });

    it('returns warning theme classes for a dev prerelease', () => {
      const color = versionApi.getVersionBadgeColor('1.0.0-dev');
      expect(color).toBe('bg-theme-warning-bg text-theme-warning-fg');
    });

    it('returns error theme classes for an alpha prerelease', () => {
      const color = versionApi.getVersionBadgeColor('1.0.0-alpha.1');
      expect(color).toBe('bg-theme-error-bg text-theme-error-fg');
    });

    it('returns warning theme classes for a beta prerelease', () => {
      const color = versionApi.getVersionBadgeColor('1.0.0-beta.2');
      expect(color).toBe('bg-theme-warning-bg text-theme-warning-fg');
    });

    it('returns info theme classes for an rc prerelease', () => {
      const color = versionApi.getVersionBadgeColor('2.0.0-rc.1');
      expect(color).toBe('bg-theme-info-bg text-theme-info-fg');
    });

    it('returns success theme classes for a version with no prerelease', () => {
      const color = versionApi.getVersionBadgeColor('0.0.1');
      expect(color).toBe('bg-theme-success-bg text-theme-success-fg');
    });

    it('handles a pure "dev" prerelease string (no version suffix)', () => {
      const color = versionApi.getVersionBadgeColor('0.1.0-dev');
      expect(color).toBe('bg-theme-warning-bg text-theme-warning-fg');
    });
  });
});
