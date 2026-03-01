/**
 * Git Providers API - Re-export from modular structure
 *
 * This file maintains backward compatibility by re-exporting the unified API
 * from the new modular structure in ./git/
 *
 * For new code, prefer importing directly from the specific modules:
 * - import { providersApi } from './git/providersApi'
 * - import { credentialsApi } from './git/credentialsApi'
 * - etc.
 */

// Re-export unified API for backward compatibility
export { gitProvidersApi } from './git';

// Re-export individual APIs for direct imports
export {
  providersApi,
  credentialsApi,
  repositoriesApi,
  pipelinesApi,
  webhooksApi,
  runnersApi,
  schedulesApi,
  approvalsApi,
  triggersApi,
} from './git';
