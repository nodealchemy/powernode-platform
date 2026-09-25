import { apiClient } from '@/shared/services/apiClient';
import { skillGraphApi } from '../skillGraphApi';

jest.mock('@/shared/services/apiClient', () => ({
  apiClient: { get: jest.fn(), post: jest.fn(), patch: jest.fn(), delete: jest.fn() },
}));

const mockGet = apiClient.get as jest.Mock;
const mockPost = apiClient.post as jest.Mock;

// fc-39: skillLifecycleApi merged into the one /ai/skill_graph client. The
// lifecycle methods return the { success, data | error } result shape; the
// fixtures are the real server envelope as axios delivers it.
describe('skillGraphApi (skill lifecycle, /ai/skill_graph)', () => {
  beforeEach(() => {
    mockGet.mockReset();
    mockPost.mockReset();
  });

  it('lists proposals with paging and a status filter', async () => {
    const body = { success: true, data: { proposals: [{ id: 'p1' }] } };
    mockGet.mockResolvedValue({ data: body });

    await expect(skillGraphApi.getProposals(2, 'proposed')).resolves.toEqual(body);
    expect(mockGet).toHaveBeenCalledWith('/ai/skill_graph/proposals?page=2&per_page=20&status=proposed');
  });

  it('turns a server error into a failed result carrying the server message', async () => {
    mockPost.mockRejectedValue({ response: { data: { success: false, error: 'Not allowed' } } });

    await expect(skillGraphApi.approveProposal('p1')).resolves.toEqual({ success: false, error: 'Not allowed' });
    expect(mockPost).toHaveBeenCalledWith('/ai/skill_graph/proposals/p1/approve');
  });

  it('records a skill outcome', async () => {
    mockPost.mockResolvedValue({ data: { success: true } });

    await skillGraphApi.recordOutcome('s1', true);
    expect(mockPost).toHaveBeenCalledWith('/ai/skill_graph/record_outcome', { skill_id: 's1', successful: true });
  });
});
