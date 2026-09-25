/**
 * DevOps Feature Module
 *
 * Git providers, CI/CD pipelines, integrations, and webhooks
 */

// Git provider management (primary exports)
export {
  CredentialModal,
  CommitDetailModal,
  useGitProviders,
  useGitCredentials,
} from './git';

// Re-export git types with explicit naming
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
  GitCommit,
  GitCommitDetail,
  GitBranch,
  GitTag,
} from './git';

// CI/CD Pipelines (use DevOps prefix to avoid git collisions)
export {
  JobLogViewer,
  StepApprovalSettings,
} from './pipelines/components';

export {
  useJobLogsWebSocket,
} from './pipelines/hooks';

// Third-party integrations
export * from './integrations';

// Webhook management
export * from './webhooks';

// Container Orchestration
export * from './containers';

// Note: For pipeline/repository hooks that have naming collisions with git:
// - Import from './pipelines' for DevOps CI/CD context
// - Import from './git' for Git provider context
