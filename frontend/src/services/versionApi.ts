import { api } from './api';

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
    } catch (error: any) {
      return {
        success: false,
        data: {} as VersionInfo,
        error: error.response?.data?.error || 'Failed to fetch version info'
      };
    }
  },

  // Get full version info
  async getFullVersion(): Promise<FullVersionResponse> {
    try {
      const response = await api.get('/version/full');
      return response.data;
    } catch (error: any) {
      return {
        success: false,
        data: {} as FullVersionInfo,
        error: error.response?.data?.error || 'Failed to fetch full version info'
      };
    }
  },

  // Get health status
  async getHealth(): Promise<HealthResponse> {
    try {
      const response = await api.get('/version/health');
      return response.data;
    } catch (error: any) {
      return {
        success: false,
        data: {} as HealthInfo,
        error: error.response?.data?.error || 'Failed to fetch health info'
      };
    }
  },

  // Get frontend version from package.json
  getFrontendVersion(): string {
    // Try environment variable first, then fall back to package.json version
    return process.env.REACT_APP_VERSION || process.env.npm_package_version || '0.0.1-dev';
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
      return 'bg-yellow-100 text-yellow-800';
    } else if (parsed.prerelease?.includes('alpha')) {
      return 'bg-red-100 text-red-800';
    } else if (parsed.prerelease?.includes('beta')) {
      return 'bg-orange-100 text-orange-800';
    } else if (parsed.prerelease?.includes('rc')) {
      return 'bg-blue-100 text-blue-800';
    } else {
      return 'bg-green-100 text-green-800';
    }
  }
};

export default versionApi;