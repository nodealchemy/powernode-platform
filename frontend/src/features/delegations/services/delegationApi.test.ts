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
