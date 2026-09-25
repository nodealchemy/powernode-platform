import { apiClient } from '@/shared/services/apiClient';
import { decideApprovalRequest } from './approvalsApi';

jest.mock('@/shared/services/apiClient', () => ({
  apiClient: { get: jest.fn(), post: jest.fn() },
}));

const mockPost = apiClient.post as jest.Mock;

// Offer 01a0d711: decideApprovalRequest is the notification panel's approve
// door, so it takes the one-shot revealed_result exactly as useApproveAction does.
describe('decideApprovalRequest', () => {
  beforeEach(() => mockPost.mockReset());

  it('hands a revealed_result to the callback and strips it from the returned request', async () => {
    mockPost.mockResolvedValue({
      data: { success: true, data: { id: 'req-1', status: 'approved', revealed_result: { token: 'tok_once', blank: '' } } },
    });
    const onRevealedResult = jest.fn();

    const result = await decideApprovalRequest('req-1', 'approve', { comments: 'ok', onRevealedResult });

    expect(mockPost).toHaveBeenCalledWith('/ai/autonomy/approvals/req-1/approve', { comments: 'ok' });
    expect(onRevealedResult).toHaveBeenCalledTimes(1);
    expect(onRevealedResult).toHaveBeenCalledWith({ token: 'tok_once' });
    expect(result).toEqual({ id: 'req-1', status: 'approved' });
    expect(JSON.stringify(result)).not.toContain('tok_once');
  });

  it('does not call the callback when nothing revealable came back', async () => {
    mockPost.mockResolvedValue({ data: { success: true, data: { id: 'req-1', status: 'rejected' } } });
    const onRevealedResult = jest.fn();

    const result = await decideApprovalRequest('req-1', 'reject', { onRevealedResult });

    expect(mockPost).toHaveBeenCalledWith('/ai/autonomy/approvals/req-1/reject', { comments: undefined });
    expect(onRevealedResult).not.toHaveBeenCalled();
    expect(result).toEqual({ id: 'req-1', status: 'rejected' });
  });

  it('returns null for an empty envelope', async () => {
    mockPost.mockResolvedValue({ data: { success: true } });

    await expect(decideApprovalRequest('req-1', 'approve', { onRevealedResult: jest.fn() })).resolves.toBeNull();
  });
});
