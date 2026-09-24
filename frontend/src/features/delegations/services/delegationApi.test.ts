import { delegationApi } from './delegationApi';

const mockDelete = jest.fn();
const mockPost = jest.fn();
const mockPatch = jest.fn();
const mockGet = jest.fn();

jest.mock('@/shared/services/api', () => ({
  api: {
    get: (...args: unknown[]) => mockGet(...args),
    post: (...args: unknown[]) => mockPost(...args),
    patch: (...args: unknown[]) => mockPatch(...args),
    delete: (...args: unknown[]) => mockDelete(...args),
  },
}));

/**
 * THE REASON LIVES IN `details`, NOT IN `error`.
 *
 * Every service-level refusal the delegations API can raise -- privilege escalation,
 * an out-of-role permission name, the widening removal -- is rendered by
 * ApiResponse#render_error as
 *
 *   { success: false, error: "<generic label>", details: ["<the real reason>"] }
 *
 * (server/app/controllers/concerns/api_response.rb builds `details` from the
 * `details:` kwarg; Api::V1::DelegationsController#remove_permission passes
 * `result[:errors]` there and gives `error` only the generic
 * "Failed to remove permission"). There is no `message` key on that shape at all.
 *
 * So a client that maps only `message || error` shows the operator a label with no
 * reason -- the exact "failed silently" the permission-set editor's error surface
 * exists to prevent.
 */
describe('delegationApi error mapping', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  const rejectWith = (mock: jest.Mock, data: unknown) => {
    mock.mockRejectedValue({ response: { data } });
  };

  it('surfaces the render_error `details` reason, not just the generic label', async () => {
    rejectWith(mockDelete, {
      success: false,
      error: 'Failed to remove permission',
      details: [
        'Removing this permission would widen the delegation to the full Finance role, granting: business.billing.refund. Update the delegation\'s permissions or revoke it instead.',
      ],
    });

    await expect(
      delegationApi.removePermissionFromDelegation('del-1', 'business.billing.read')
    ).rejects.toThrow(/would widen the delegation to the full Finance role/);
  });

  it('keeps the generic label alongside the reason so the failed VERB stays visible', async () => {
    rejectWith(mockPost, {
      success: false,
      error: 'Failed to add permission',
      details: ['business.billing.refund is not granted by the Finance role'],
    });

    await expect(
      delegationApi.addPermissionToDelegation('del-1', 'business.billing.refund')
    ).rejects.toThrow(/Failed to add permission: business\.billing\.refund is not granted by the Finance role/);
  });

  it('joins every reason when the service reports more than one', async () => {
    rejectWith(mockPatch, {
      success: false,
      error: 'Failed to update delegation',
      details: ['first reason', 'second reason'],
    });

    await expect(
      delegationApi.updateDelegation('del-1', { permission_names: ['a'] })
    ).rejects.toThrow(/first reason; second reason/);
  });

  it('accepts a bare-string `details` as well as an array', async () => {
    rejectWith(mockDelete, {
      success: false,
      error: 'Failed to remove permission',
      details: 'the only reason',
    });

    await expect(
      delegationApi.removePermissionFromDelegation('del-1', 'business.billing.read')
    ).rejects.toThrow(/the only reason/);
  });

  it('falls back to the generic label when the envelope carries no details', async () => {
    rejectWith(mockDelete, { success: false, error: 'Failed to remove permission' });

    await expect(
      delegationApi.removePermissionFromDelegation('del-1', 'business.billing.read')
    ).rejects.toThrow('Failed to remove permission');
  });

  it('still prefers an explicit `message` where an endpoint sends one', async () => {
    rejectWith(mockDelete, { message: 'A plain message', error: 'ignored' });

    await expect(
      delegationApi.removePermissionFromDelegation('del-1', 'business.billing.read')
    ).rejects.toThrow('A plain message');
  });
});

/**
 * fc-20 review: two live bugs fixed together, so both are pinned here.
 *
 * 1. Every endpoint literal hardcoded '/api/v1' on top of `api`'s own
 *    baseURL (which already is '/api/v1'), so every real request 404'd as
 *    '/api/v1/api/v1/...' (P16, no-double-api-v1-prefix.test.ts). Pinned by
 *    asserting the LITERAL path `api.<verb>` receives.
 * 2. `apiRequest` returned the whole `{success, data}` envelope
 *    (ApiResponse#render_success) instead of unwrapping it, so every
 *    resolved value was one level too deep relative to what the exported
 *    types (DelegationsResponse, DelegationResponse, ...) declare. Pinned by
 *    asserting the RESOLVED value is the inner payload, not the envelope.
 */
describe('delegationApi — real endpoint paths and envelope unwrapping', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  const envelope = (data: unknown) => ({ data: { success: true, data } });

  it('getDelegations hits the real path with no doubled prefix, and unwraps the envelope', async () => {
    mockGet.mockResolvedValue(envelope({ delegations: [ { id: 'del-1' } ], meta: { total_count: 1 } }));

    const result = await delegationApi.getDelegations();

    expect(mockGet).toHaveBeenCalledWith('/accounts/current/delegations');
    expect(result).toEqual({ delegations: [ { id: 'del-1' } ], meta: { total_count: 1 } });
  });

  it('getDelegations appends filters as a query string on the same real path', async () => {
    mockGet.mockResolvedValue(envelope({ delegations: [], meta: { total_count: 0 } }));

    await delegationApi.getDelegations({ status: 'active' });

    expect(mockGet).toHaveBeenCalledWith('/accounts/current/delegations?status=active');
  });

  it('getDelegation hits the real per-id path and unwraps the envelope', async () => {
    mockGet.mockResolvedValue(envelope({ delegation: { id: 'del-1' } }));

    const result = await delegationApi.getDelegation('del-1');

    expect(mockGet).toHaveBeenCalledWith('/accounts/current/delegations/del-1');
    expect(result).toEqual({ delegation: { id: 'del-1' } });
  });

  it('createDelegation POSTs the real path with a `delegation` envelope param', async () => {
    mockPost.mockResolvedValue(envelope({ delegation: { id: 'del-1' }, message: 'Delegation created successfully' }));

    const result = await delegationApi.createDelegation({ delegated_user_email: 'a@example.com' });

    expect(mockPost).toHaveBeenCalledWith('/accounts/current/delegations', {
      delegation: { delegated_user_email: 'a@example.com' },
    });
    expect(result).toEqual({ delegation: { id: 'del-1' }, message: 'Delegation created successfully' });
  });

  it('revokeDelegation PATCHes the real /revoke path and unwraps the envelope', async () => {
    mockPatch.mockResolvedValue(envelope({ delegation: { id: 'del-1', status: 'revoked' }, message: 'Delegation revoked successfully' }));

    const result = await delegationApi.revokeDelegation('del-1');

    expect(mockPatch).toHaveBeenCalledWith('/accounts/current/delegations/del-1/revoke', undefined);
    expect(result).toEqual({ delegation: { id: 'del-1', status: 'revoked' }, message: 'Delegation revoked successfully' });
  });

  it('deleteDelegation DELETEs the real per-id path and unwraps a message-only envelope', async () => {
    mockDelete.mockResolvedValue(envelope({ message: 'Delegation revoked successfully' }));

    const result = await delegationApi.deleteDelegation('del-1');

    expect(mockDelete).toHaveBeenCalledWith('/accounts/current/delegations/del-1');
    expect(result).toEqual({ message: 'Delegation revoked successfully' });
  });

  it('getAvailablePermissions hits the real /available_permissions path and unwraps to the bare array', async () => {
    mockGet.mockResolvedValue(envelope({ permissions: [ { name: 'business.billing.read', key: 'business.billing.read', resource: 'business.billing', action: 'read', description: 'View billing' } ], role_id: 'r-1' }));

    const result = await delegationApi.getAvailablePermissions('r-1');

    expect(mockGet).toHaveBeenCalledWith('/accounts/current/delegations/available_permissions?role_id=r-1');
    expect(result).toEqual([ { name: 'business.billing.read', key: 'business.billing.read', resource: 'business.billing', action: 'read', description: 'View billing' } ]);
  });

  it('addPermissionToDelegation POSTs the real /permissions path', async () => {
    mockPost.mockResolvedValue(envelope({ delegation: { id: 'del-1' }, message: 'Permission added successfully' }));

    await delegationApi.addPermissionToDelegation('del-1', 'business.billing.read');

    expect(mockPost).toHaveBeenCalledWith('/accounts/current/delegations/del-1/permissions', {
      permission_name: 'business.billing.read',
    });
  });

  it('removePermissionFromDelegation DELETEs the real /permissions/:name path', async () => {
    mockDelete.mockResolvedValue(envelope({ delegation: { id: 'del-1' }, message: 'Permission removed successfully' }));

    await delegationApi.removePermissionFromDelegation('del-1', 'business.billing.read');

    expect(mockDelete).toHaveBeenCalledWith('/accounts/current/delegations/del-1/permissions/business.billing.read');
  });

  it('getAvailableRoles fetches through rolesApi.getRoles() and excludes only the owner role', async () => {
    mockGet.mockResolvedValue({
      data: {
        success: true,
        data: [
          { id: 'r-1', name: 'owner', description: 'Owner' },
          { id: 'r-2', name: 'manager', description: 'Manager' },
        ],
      },
    });

    const result = await delegationApi.getAvailableRoles();

    expect(mockGet).toHaveBeenCalledWith('/roles');
    expect(result).toEqual([ { id: 'r-2', name: 'manager', description: 'Manager' } ]);
  });
});
