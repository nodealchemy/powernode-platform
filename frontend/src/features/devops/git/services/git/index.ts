/**
 * Git Services - Modular API Module
 *
 * Re-exports each Git domain API individually. The old unified spread-barrel
 * (a pure `{...providersApi, ...credentialsApi, ...}` merge with no behaviour
 * of its own) was deleted fc-24 — every former caller now imports the
 * specific domain API it actually uses from here. fc-39 gave the providers
 * and webhooks APIs git-prefixed names (gitProvidersApi, gitWebhooksApi) so
 * no two clients across core and extensions share an export name.
 */

export { gitProvidersApi } from './providersApi';
export { credentialsApi } from './credentialsApi';
export { repositoriesApi } from './repositoriesApi';
export { pipelinesApi } from './pipelinesApi';
export { gitWebhooksApi } from './webhooksApi';
export { runnersApi } from './runnersApi';
export { schedulesApi } from './schedulesApi';
export { approvalsApi } from './approvalsApi';
