// Git Commit and Diff Types (Comprehensive Git Viewing)

import type { PaginationInfo } from './repositories';

/**
 * Basic commit author/committer information
 */
export interface GitCommitAuthor {
  name: string;
  email: string;
  date: string;
  username?: string;
  avatar_url?: string;
}

/**
 * Statistics for a commit (additions, deletions, files changed)
 */
export interface GitCommitStats {
  additions: number;
  deletions: number;
  total: number;
  files_changed: number;
}

/**
 * Basic commit information (for lists)
 */
export interface GitCommit {
  sha: string;
  short_sha: string;
  message: string;
  title: string;  // First line of message
  body?: string;  // Rest of message after first line
  author: GitCommitAuthor;
  committer: GitCommitAuthor;
  authored_date: string;
  committed_date: string;
  web_url?: string;
  parent_shas: string[];
  is_merge: boolean;
  is_verified: boolean;
  verification?: {
    verified: boolean;
    reason: string;
    signature?: string;
    payload?: string;
  };
}

/**
 * File changed in a commit
 */
export interface GitCommitFile {
  sha?: string;
  filename: string;
  status: 'added' | 'removed' | 'modified' | 'renamed' | 'copied' | 'changed' | 'unchanged';
  additions: number;
  deletions: number;
  changes: number;
  patch?: string;
  previous_filename?: string;
  blob_url?: string;
  raw_url?: string;
  contents_url?: string;
}

/**
 * Detailed commit information including files and stats
 */
export interface GitCommitDetail extends GitCommit {
  stats: GitCommitStats;
  files: GitCommitFile[];
  tree_sha?: string;
  repository?: {
    id: string;
    name: string;
    full_name: string;
  };
}

/**
 * A single line in a diff hunk
 */
export interface GitDiffLine {
  type: 'context' | 'addition' | 'deletion' | 'header';
  content: string;
  old_line_number?: number;
  new_line_number?: number;
}

/**
 * A hunk (section) within a file diff
 */
export interface GitDiffHunk {
  header: string;
  old_start: number;
  old_lines: number;
  new_start: number;
  new_lines: number;
  lines: GitDiffLine[];
}

/**
 * Diff for a single file
 */
export interface GitFileDiff {
  filename: string;
  status: 'added' | 'removed' | 'modified' | 'renamed' | 'copied';
  additions: number;
  deletions: number;
  changes: number;
  previous_filename?: string;
  hunks: GitDiffHunk[];
  is_binary: boolean;
  is_large: boolean;
  truncated: boolean;
  raw_patch?: string;
}

/**
 * Complete diff between two commits or a commit and its parent
 */
export interface GitDiff {
  base_sha: string;
  head_sha: string;
  base_ref?: string;
  head_ref?: string;
  ahead_by?: number;
  behind_by?: number;
  total_commits?: number;
  files: GitFileDiff[];
  stats: GitCommitStats;
  status: 'identical' | 'ahead' | 'behind' | 'diverged';
  commits?: GitCommit[];
}

/**
 * Branch information with latest commit
 */
export interface GitBranch {
  name: string;
  sha: string;
  is_default: boolean;
  is_protected: boolean;
  protection_rules?: {
    required_reviews: number;
    dismiss_stale_reviews: boolean;
    require_code_owner_reviews: boolean;
    require_signed_commits: boolean;
    enforce_admins: boolean;
    required_status_checks: string[];
  };
  commit?: GitCommit;
  web_url?: string;
}

/**
 * Tag information
 */
export interface GitTag {
  name: string;
  sha: string;
  message?: string;
  tagger?: GitCommitAuthor;
  commit?: GitCommit;
  web_url?: string;
  is_release: boolean;
  release?: {
    id: string;
    name: string;
    body?: string;
    draft: boolean;
    prerelease: boolean;
    created_at: string;
    published_at?: string;
    assets_count: number;
  };
}

/**
 * Tree entry (file or directory in a repository tree)
 */
export interface GitTreeEntry {
  path: string;
  name: string;
  type: 'blob' | 'tree' | 'commit';
  mode: string;
  sha: string;
  size?: number;
  url?: string;
}

/**
 * Repository tree (directory listing)
 */
export interface GitTree {
  sha: string;
  url?: string;
  entries: GitTreeEntry[];
  truncated: boolean;
}

/**
 * File content from repository
 */
export interface GitFileContent {
  name: string;
  path: string;
  sha: string;
  size: number;
  type: 'file' | 'dir' | 'symlink' | 'submodule';
  content?: string;
  encoding?: 'base64' | 'utf-8' | 'none';
  target?: string;  // For symlinks
  submodule_url?: string;  // For submodules
  download_url?: string;
  web_url?: string;
  language?: string;
  is_binary: boolean;
  lines_count?: number;
}

/**
 * File blame information (who changed each line)
 */
export interface GitBlameRange {
  commit: GitCommit;
  start_line: number;
  end_line: number;
  lines: string[];
}

export interface GitFileBlame {
  path: string;
  sha: string;
  ranges: GitBlameRange[];
}

/**
 * Commit comparison between two refs
 */
export interface GitCommitComparison {
  url?: string;
  status: 'identical' | 'ahead' | 'behind' | 'diverged';
  ahead_by: number;
  behind_by: number;
  total_commits: number;
  base_commit: GitCommit;
  head_commit: GitCommit;
  merge_base_commit: GitCommit;
  commits: GitCommit[];
  files: GitCommitFile[];
  diff_stats: GitCommitStats;
}

// Response types for git viewing APIs

export interface GitCommitsResponse {
  commits: GitCommit[];
  pagination: PaginationInfo;
  repository?: {
    id: string;
    name: string;
    default_branch: string;
  };
}

export interface GitBranchesResponse {
  branches: GitBranch[];
  pagination: PaginationInfo;
  default_branch?: string;
}

export interface GitTagsResponse {
  tags: GitTag[];
  pagination: PaginationInfo;
}

export interface GitTreeResponse {
  tree: GitTree;
  commit_sha: string;
  path: string;
  repository?: {
    id: string;
    name: string;
  };
}
