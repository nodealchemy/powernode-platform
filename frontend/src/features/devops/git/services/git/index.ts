/**
 * Git Services - Unified API Module
 *
 * This module combines all Git-related API services into a single unified export
 * while also allowing direct imports of individual domain APIs.
 */

import { providersApi } from './providersApi';
import { credentialsApi } from './credentialsApi';
import { repositoriesApi } from './repositoriesApi';
import { pipelinesApi } from './pipelinesApi';
import { webhooksApi } from './webhooksApi';
import { runnersApi } from './runnersApi';
import { schedulesApi } from './schedulesApi';
import { approvalsApi } from './approvalsApi';
import { triggersApi } from './triggersApi';

/**
 * Unified Git Providers API
 * Combines all domain-specific APIs for backward compatibility
 */
export const gitProvidersApi = {
  // Providers
  ...providersApi,

  // Credentials
  ...credentialsApi,

  // Repositories
  ...repositoriesApi,

  // Pipelines
  ...pipelinesApi,

  // Webhooks
  ...webhooksApi,

  // Runners
  ...runnersApi,

  // Schedules
  ...schedulesApi,

  // Approvals
  ...approvalsApi,

  // Triggers
  ...triggersApi,
};

// Export individual APIs for direct imports
export { providersApi } from './providersApi';
export { credentialsApi } from './credentialsApi';
export { repositoriesApi } from './repositoriesApi';
export { pipelinesApi } from './pipelinesApi';
export { webhooksApi } from './webhooksApi';
export { runnersApi } from './runnersApi';
export { schedulesApi } from './schedulesApi';
export { approvalsApi } from './approvalsApi';
export { triggersApi } from './triggersApi';
