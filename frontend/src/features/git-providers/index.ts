// Git Providers Feature - Main exports

// Components
export { GitProvidersPage } from './components/GitProvidersPage';
export { GitProviderCard } from './components/GitProviderCard';
export { CredentialModal } from './components/CredentialModal';
export { RepositoryList } from './components/RepositoryList';
export { PipelineList } from './components/PipelineList';
export { DiffViewer } from './components/DiffViewer';
export { CommitDetailModal } from './components/CommitDetailModal';

// Services
export { gitProvidersApi } from './services/gitProvidersApi';

// Hooks
export { useGitProviders, useGitCredentials } from './hooks/useGitProviders';
export { useRepositories, useRepository } from './hooks/useRepositories';
export {
  usePipelines,
  usePipeline,
  usePipelineJobs,
  useJobLogs,
} from './hooks/usePipelines';

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
  SyncRepositoriesResult,
  PaginationInfo,
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
