import { api } from '@/shared/services/api';
import { isErrorWithResponse, getErrorMessage } from '@/shared/utils/errorHandling';
import { getAppVersion, getBuildInfo, type BuildInfo } from '@/shared/utils/env';

export type { BuildInfo };

export interface VersionInfo {
  version: string;
  major: number;
  minor: number;
  patch: number;
  prerelease?: string;
  build_date: string;
  git_commit: string;
  // Build identity (Powernode::Version#semantic_version, 2026-09). Optional so
  // a frontend talking to an older backend still renders.
  display?: string;
  release?: boolean;
  short_sha?: string | null;
  git_branch?: string;
  git_tag?: string | null;
  built_at?: string | null;
}

/** The minimum either side needs to apply the display contract. */
export interface DisplayableVersion {
  version: string;
  display?: string;
  short_sha?: string | null;
  release?: boolean;
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
      const response = await api.get<VersionResponse>('/version');
      return response.data;
    } catch (error) {
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
      const response = await api.get<FullVersionResponse>('/version/full');
      return response.data;
    } catch (error) {
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
      const response = await api.get<HealthResponse>('/version/health');
      return response.data;
    } catch (error) {
      return {
        success: false,
        data: {} as HealthInfo,
        error: isErrorWithResponse(error) ? (error.response?.data?.error || 'Health service unavailable') : getErrorMessage(error)
      };
    }
  },

  // Get frontend version from the VERSION file (injected at build time).
  getFrontendVersion(): string {
    return getAppVersion();
  },

  // The bundle's build identity (sha / branch / tag / release verdict).
  getFrontendBuildInfo(): BuildInfo {
    return getBuildInfo();
  },

  // DISPLAY CONTRACT, shared with Powernode::Version#display_version:
  //   release build         -> "X.Y.Z"
  //   any other known build -> "<7-char sha>"
  //   no identity at all    -> "X.Y.Z-dev"
  // A server-provided `display` wins so both halves can only ever disagree by
  // the server's own choice.
  displayVersion(info: DisplayableVersion): string {
    if (info.display) return info.display;
    if (info.release) return info.version;
    if (info.short_sha) return info.short_sha;
    return info.version.endsWith('-dev') ? info.version : `${info.version}-dev`;
  },

  // Tooltip text for a build: full sha, branch and tag when known.
  describeBuild(label: string, info: { version: string; sha?: string | null; short_sha?: string | null; branch?: string; git_branch?: string; tag?: string | null; git_tag?: string | null; release?: boolean }): string {
    const sha = info.sha ?? info.short_sha ?? null;
    const branch = info.branch ?? info.git_branch;
    const tag = info.tag ?? info.git_tag;
    const parts = [`${label} ${info.version}`];
    if (sha) parts.push(`commit ${sha}`);
    if (branch && branch !== 'unknown') parts.push(`branch ${branch}`);
    if (tag) parts.push(`tag ${tag}`);
    parts.push(info.release ? 'release build' : 'incremental build');
    return parts.join(' · ');
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
      return 'bg-theme-warning-bg text-theme-warning-fg';
    } else if (parsed.prerelease?.includes('alpha')) {
      return 'bg-theme-error-bg text-theme-error-fg';
    } else if (parsed.prerelease?.includes('beta')) {
      return 'bg-theme-warning-bg text-theme-warning-fg';
    } else if (parsed.prerelease?.includes('rc')) {
      return 'bg-theme-info-bg text-theme-info-fg';
    } else {
      return 'bg-theme-success-bg text-theme-success-fg';
    }
  }
};

export default versionApi;