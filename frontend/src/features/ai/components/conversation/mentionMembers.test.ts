import { gatherMentionMembers } from './mentionMembers';
import { featureRegistry } from '@/shared/services/featureRegistry';
import { apiClient } from '@/shared/services/apiClient';
import { logger } from '@/shared/utils/logger';

jest.mock('@/shared/services/apiClient', () => ({
  apiClient: { get: jest.fn(), post: jest.fn() },
}));

const member = (id: string) => ({ id, name: id, role: 'member', agent_type: 'human', is_lead: false });

// The @-mention picker lists workspace members plus whatever extra members
// extensions contribute through featureRegistry mention sources. Core names
// no extension route for them.
describe('gatherMentionMembers', () => {
  afterEach(() => featureRegistry.clear());

  it('returns only workspace members, and calls no API itself, when nothing is registered', async () => {
    const members = await gatherMentionMembers(async () => [member('w1')]);

    expect(members.map((m) => m.id)).toEqual(['w1']);
    expect(apiClient.get).not.toHaveBeenCalled();
  });

  it('merges the members every registered source returns', async () => {
    featureRegistry.registerMentionSources('ext', [async () => [member('p1'), member('p2')]]);

    const members = await gatherMentionMembers(async () => [member('w1')]);

    expect(members.map((m) => m.id)).toEqual(['w1', 'p1', 'p2']);
  });

  it('drops a rejecting source, logging it at debug level only', async () => {
    const debug = jest.spyOn(logger, 'debug').mockImplementation(() => undefined);
    const error = jest.spyOn(logger, 'error').mockImplementation(() => undefined);
    const warn = jest.spyOn(logger, 'warn').mockImplementation(() => undefined);
    featureRegistry.registerMentionSources('ext', [
      async () => {
        throw new Error('404');
      },
      async () => [member('p1')],
    ]);

    const members = await gatherMentionMembers(async () => [member('w1')]);

    expect(members.map((m) => m.id)).toEqual(['w1', 'p1']);
    expect(debug).toHaveBeenCalledTimes(1);
    expect(error).not.toHaveBeenCalled();
    expect(warn).not.toHaveBeenCalled();
    [debug, error, warn].forEach((s) => s.mockRestore());
  });

  it('replaces, not appends, a namespace\'s sources when it registers again', async () => {
    featureRegistry.registerMentionSources('ext', [async () => [member('old')]]);
    featureRegistry.registerMentionSources('ext', [async () => [member('new')]]);

    const members = await gatherMentionMembers(async () => [member('w1')]);

    expect(members.map((m) => m.id)).toEqual(['w1', 'new']);
  });

  it('drops a source that throws synchronously instead of rejecting', async () => {
    const debug = jest.spyOn(logger, 'debug').mockImplementation(() => undefined);
    featureRegistry.registerMentionSources('ext', [
      (() => {
        throw new Error('sync');
      }) as unknown as () => Promise<never>,
      async () => [member('p1')],
    ]);

    const members = await gatherMentionMembers(async () => [member('w1')]);

    expect(members.map((m) => m.id)).toEqual(['w1', 'p1']);
    expect(debug).toHaveBeenCalledTimes(1);
    debug.mockRestore();
  });

  it('treats a source that resolves to a non-array as contributing nothing', async () => {
    featureRegistry.registerMentionSources('ext', [
      async () => ({ members: [member('x')] }) as unknown as never[],
      async () => null as unknown as never[],
      async () => [member('p1')],
    ]);

    const members = await gatherMentionMembers(async () => [member('w1')]);

    expect(members.map((m) => m.id)).toEqual(['w1', 'p1']);
  });
});
