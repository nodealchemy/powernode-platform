import type { AutonomyConfigSource } from '@/shared/types/autonomy';
import { policyBucket } from '../policyBucket';

/**
 * Points the shared useAutonomyConfig hook at core's intervention-policy
 * endpoints: the account's rows grouped by registered policy domain, and the
 * bulk save that writes each edited control back to the row it was rendered
 * from (`scope` + `agent_id`, which every grouped row carries).
 *
 * `bucketForRow` is set, so a row the payload cannot place answers `null` and
 * the panel renders it read-only rather than under an invented group.
 */
export const interventionPolicyConfigSource: AutonomyConfigSource = {
  fetchEndpoint: '/ai/intervention_policies/grouped',
  updateEndpoint: '/ai/intervention_policies/bulk',
  bucketForRow: policyBucket,
};
