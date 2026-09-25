// Git Providers Feature - Main exports

// Constants
export { GIT_PROVIDER_BRAND_BG } from './constants';

// Components
export { CredentialModal } from './components/CredentialModal';
export { CommitDetailModal } from './components/CommitDetailModal';

// Services
export { repositoriesApi } from './services/git/repositoriesApi';

// Hooks
export { useGitProviders, useGitCredentials } from './hooks/useGitProviders';

// Types
export type {
  GitProvider,
  GitProviderDetail,
  GitCredential,
  GitCredentialDetail,
  GitRepository,
  GitRepositoryDetail,
  GitPipeline,
  GitWebhookEvent,
  AvailableProvider,
  CreateCredentialData,
  PipelineStats,
  WebhookEventStats,
  ConnectionTestResult,
  PaginationInfo,
  BranchFilterType,
  // Commit and diff types
  GitCommit,
  GitCommitDetail,
  GitCommitFile,
  GitCommitStats,
  GitCommitAuthor,
  GitDiff,
  GitFileDiff,
  GitDiffHunk,
  GitDiffLine,
  GitFileContent,
  GitTree,
  GitTreeEntry,
  GitBranch,
  GitTag,
  GitCommitComparison,
} from './types';
