/**
 * Git Services - Modular API Module
 *
 * Re-exports each Git domain API individually. The unified `gitProvidersApi`
 * spread-barrel (a pure `{...providersApi, ...credentialsApi, ...}` merge
 * with no behaviour of its own) was deleted fc-24 — every former caller now
 * imports the specific domain API it actually uses from here.
 */

export { providersApi } from './providersApi';
export { credentialsApi } from './credentialsApi';
export { repositoriesApi } from './repositoriesApi';
export { pipelinesApi } from './pipelinesApi';
export { webhooksApi } from './webhooksApi';
export { runnersApi } from './runnersApi';
export { schedulesApi } from './schedulesApi';
export { approvalsApi } from './approvalsApi';
