/**
 * Git Services - Modular API Module
 *
 * Re-exports each Git domain API individually. The old unified spread-barrel
 * (a pure `{...providersApi, ...credentialsApi, ...}` merge with no behaviour
 * of its own) was deleted fc-24 — every former caller now imports the
 * specific domain API it actually uses from here. fc-39 gave the providers
 * API a git-prefixed name (gitProvidersApi; its webhooks sibling was deleted fc-48) so
 * no two clients across core and extensions share an export name.
 */

export { gitProvidersApi } from './providersApi';
export { credentialsApi } from './credentialsApi';
export { repositoriesApi } from './repositoriesApi';
export { runnersApi } from './runnersApi';
export { approvalsApi } from './approvalsApi';
