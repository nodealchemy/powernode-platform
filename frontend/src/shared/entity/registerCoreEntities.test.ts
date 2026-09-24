import { entityRegistry } from '@/shared/services/entityRegistry';
import { registerCoreEntities } from './registerCoreEntities';

// fc-11: the Governance → Approvals tab (and its `GET
// /ai/governance/approval_requests/:id` fetch) is gone. The `approval_request`
// EntityLink type migrates to the surface that already reads a single request
// in detail — `Ai::AutonomyApprovalActions#show_approval`
// (`GET /ai/autonomy/approvals/:id`, IMP-550e44e24220 shares the serializer
// with the retired Governance read) — rather than losing its only consumer.

const mockGet = jest.fn();
jest.mock('@/shared/services/apiClient', () => ({
  __esModule: true,
  apiClient: { get: (...args: unknown[]) => mockGet(...args) },
  default: { get: (...args: unknown[]) => mockGet(...args) },
}));

describe('approval_request entity — fetchById', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    entityRegistry.clear();
    registerCoreEntities();
  });

  it('reads GET /ai/autonomy/approvals/:id, not the retired Governance approval_requests route', async () => {
    mockGet.mockResolvedValue({
      data: { data: { id: 'req-1', status: 'pending', description: 'Rotate secret for disk image webhook', current_step: 0 } },
    });

    const definition = entityRegistry.getEntity('approval_request');
    const result = await definition?.fetchById?.('req-1');

    expect(mockGet).toHaveBeenCalledTimes(1);
    expect(mockGet).toHaveBeenCalledWith('/ai/autonomy/approvals/req-1');
    // `show_approval` renders the request FLAT under `data`
    // (`render_success(data: serialize_approval_request(request, detailed: true))`)
    // — never wrapped in `{ approval_request }`, unlike the retired Governance
    // read this replaces.
    expect(result).toEqual({
      id: 'req-1', status: 'pending', description: 'Rotate secret for disk image webhook', current_step: 0,
    });
  });

  // AutonomyController#validate_permissions requires ai.agents.read on every
  // action but current_worker. The retired Governance read had NO resource
  // permission (GovernanceController#show_approval_request), so this is a
  // gate that did not exist before the migration — degrading to plain text
  // for a viewer without it, not a 403 render error, per EntityLink's
  // "omission is always safe" contract.
  it('is gated on ai.agents.read, matching AutonomyController#validate_permissions', () => {
    const definition = entityRegistry.getEntity('approval_request');
    expect(definition?.permission).toBe('ai.agents.read');
  });

  it('still labels by description, unaffected by the endpoint migration', () => {
    const definition = entityRegistry.getEntity('approval_request');
    expect(definition?.labelField).toBe('description');
  });
});
