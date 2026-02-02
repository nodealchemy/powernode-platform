import { api } from '@/shared/services/api';
import { isErrorWithResponse, getErrorMessage } from '@/shared/utils/errorHandling';

export interface VersionInfo {
  version: string;
  major: number;
  minor: number;
  patch: number;
  prerelease?: string;
  build_date: string;
  git_commit: string;
}

export interface FullVersionInfo extends VersionInfo {
  git_branch: string;
  rails_version: string;
  ruby_version: string;
  environment: string;
}

export interface HealthInfo {
  status: string;
  version: string;
  timestamp: string;
  uptime: {
    boot_time: string;
    uptime_seconds: number;
    uptime_human: string;
  };
}

export interface VersionResponse {
  success: boolean;
  data: VersionInfo;
  error?: string;
}

export interface FullVersionResponse {
  success: boolean;
  data: FullVersionInfo;
  error?: string;
}

export interface HealthResponse {
  success: boolean;
  data: HealthInfo;
  error?: string;
}

// API Service
export const versionApi = {
  // Get basic version info
  async getVersion(): Promise<VersionResponse> {
    try {
      const response = await api.get('/version');
      return response.data;
    } catch {
      // Log network errors as warnings, not errors
      return {
        success: false,
        data: {} as VersionInfo,
        error: isErrorWithResponse(error) ? (error.response?.data?.error || 'Version service unavailable') : getErrorMessage(error)
      };
    }
  },

  // Get full version info
  async getFullVersion(): Promise<FullVersionResponse> {
    try {
      const response = await api.get('/version/full');
      return response.data;
    } catch {
      return {
        success: false,
        data: {} as FullVersionInfo,
        error: isErrorWithResponse(error) ? (error.response?.data?.error || 'Full version service unavailable') : getErrorMessage(error)
      };
    }
  },

  // Get health status
  async getHealth(): Promise<HealthResponse> {
    try {
      const response = await api.get('/version/health');
      return response.data;
    } catch {
      return {
        success: false,
        data: {} as HealthInfo,
        error: isErrorWithResponse(error) ? (error.response?.data?.error || 'Health service unavailable') : getErrorMessage(error)
      };
    }
  },

  // Get frontend version from VERSION file (via environment variable)
  getFrontendVersion(): string {
    // Try Vite environment variable first (set from VERSION file), then fall back
    return import.meta.env.VITE_APP_VERSION || import.meta.env.npm_package_version || '0.0.1-dev';
  },

  // Format version for display
  formatVersion(version: string, showPrerelease: boolean = true): string {
    if (!showPrerelease) {
      const [baseVersion] = version.split('-');
      return baseVersion;
    }
    return version;
  },

  // Parse version components
  parseVersion(version: string) {
    const [baseVersion, prerelease] = version.split('-');
    const [major, minor, patch] = baseVersion.split('.').map(Number);
    
    return {
      major: major || 0,
      minor: minor || 0,
      patch: patch || 0,
      prerelease: prerelease || null,
      full: version
    };
  },

  // Compare versions (returns -1, 0, 1)
  compareVersions(version1: string, version2: string): number {
    const v1 = this.parseVersion(version1);
    const v2 = this.parseVersion(version2);

    if (v1.major !== v2.major) return v1.major - v2.major;
    if (v1.minor !== v2.minor) return v1.minor - v2.minor;
    if (v1.patch !== v2.patch) return v1.patch - v2.patch;

    // Handle prerelease versions
    if (!v1.prerelease && !v2.prerelease) return 0;
    if (!v1.prerelease && v2.prerelease) return 1;
    if (v1.prerelease && !v2.prerelease) return -1;
    
    return v1.prerelease!.localeCompare(v2.prerelease!);
  },

  // Get version badge color
  getVersionBadgeColor(version: string): string {
    const parsed = this.parseVersion(version);
    
    if (parsed.prerelease?.includes('dev')) {
      return 'bg-theme-warning-background text-theme-warning';
    } else if (parsed.prerelease?.includes('alpha')) {
      return 'bg-theme-error-background text-theme-error';
    } else if (parsed.prerelease?.includes('beta')) {
      return 'bg-theme-warning-background text-theme-warning';
    } else if (parsed.prerelease?.includes('rc')) {
      return 'bg-theme-info-background text-theme-info';
    } else {
      return 'bg-theme-success-background text-theme-success';
    }
  }
};

export default versionApi;