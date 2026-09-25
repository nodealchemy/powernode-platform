// Git Providers Feature - Main exports

// Constants
export { GIT_PROVIDER_BRAND_BG } from './constants';

// Components
export { CredentialModal } from './components/CredentialModal';
export { CommitDetailModal } from './components/CommitDetailModal';

// Services
export { repositoriesApi } from './services/git/repositoriesApi';
export { webhooksApi } from './services/git/webhooksApi';

// Hooks
export { useGitProviders, useGitCredentials } from './hooks/useGitProviders';
export { useRepositories, useRepository } from './hooks/useRepositories';

// Types
export type {
  GitProvider,
  GitProviderDetail,
  GitCredential,
  GitCredentialDetail,
  GitRepository,
  GitRepositoryDetail,
  GitPipeline,
  GitPipelineDetail,
  GitPipelineJob,
  GitPipelineJobDetail,
  GitWebhookEvent,
  GitWebhookEventDetail,
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
