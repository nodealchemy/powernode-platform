import { apiClient } from '@/shared/services/apiClient';
import {
  runComponentAction,
  openInvestigation,
  fetchRemediationRoute,
  fetchComponentEvents,
  fetchInvestigations,
  InvestigationRefusedError,
} from './platformStatusApi';
import type { ComponentAction } from '@/shared/types/platformStatus';

jest.mock('@/shared/services/apiClient', () => ({
  apiClient: {
    get: jest.fn(),
    post: jest.fn(),
    put: jest.fn(),
    patch: jest.fn(),
    delete: jest.fn(),
  },
}));

const client = apiClient as unknown as {
  get: jest.Mock;
  post: jest.Mock;
  put: jest.Mock;
  patch: jest.Mock;
  delete: jest.Mock;
};

// The status plane's two writes, executed against the api client rather than
// mocked away (C3 review F4). Every other spec in the feature mocks this whole
// module, so until this file the method switch, the body shape, the DELETE
// query-param path and the 409-to-typed-refusal mapping had never run. The
// `never` check in `runComponentAction` is a COMPILE-time guard; the runtime
// arm is asserted here.

const action = (method: ComponentAction['method']) => ({
  method,
  path: '/system/instances/i-42/cordon',
});

describe('runComponentAction', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    for (const verb of ['post', 'put', 'patch', 'delete'] as const) {
      client[verb].mockResolvedValue({ data: { success: true } });
    }
  });

  it.each([
    ['POST', 'post'],
    ['PUT', 'put'],
    ['PATCH', 'patch'],
  ] as const)('%s sends the declared path with the reason in the body', async (method, verb) => {
    await runComponentAction(action(method), { reason: 'rack decommission' });
    expect(client[verb]).toHaveBeenCalledWith('/system/instances/i-42/cordon', {
      reason: 'rack decommission',
    });
  });

  it('sends NO body when no reason was given, rather than an empty reason', async () => {
    // `{reason: ""}` would reach an audit log as a reason that was recorded and
    // was blank — a different fact from "none was asked for".
    await runComponentAction(action('POST'));
    expect(client.post).toHaveBeenCalledWith('/system/instances/i-42/cordon', undefined);
  });

  it('DELETE carries the reason as a query param, because axios delete has no body argument', async () => {
    await runComponentAction(action('DELETE'), { reason: 'orphaned' });
    expect(client.delete).toHaveBeenCalledWith('/system/instances/i-42/cordon', {
      params: { reason: 'orphaned' },
    });
  });

  it('DELETE without a reason sends no params at all', async () => {
    await runComponentAction(action('DELETE'));
    expect(client.delete).toHaveBeenCalledWith('/system/instances/i-42/cordon', undefined);
  });

  it('refuses a method it does not know at RUNTIME, not only at compile time', async () => {
    await expect(
      runComponentAction({ method: 'GET' as unknown as ComponentAction['method'], path: '/x' })
    ).rejects.toThrow(/Unsupported action method: GET/);
    // And it touched nothing on the way to refusing.
    for (const verb of ['get', 'post', 'put', 'patch', 'delete'] as const) {
      expect(client[verb]).not.toHaveBeenCalled();
    }
  });

  it('propagates a server refusal rather than swallowing it', async () => {
    client.post.mockRejectedValue(new Error('403 Forbidden'));
    await expect(runComponentAction(action('POST'))).rejects.toThrow('403 Forbidden');
  });
});

describe('openInvestigation', () => {
  beforeEach(() => jest.clearAllMocks());

  it('returns the investigation on 201', async () => {
    client.post.mockResolvedValue({ data: { data: { investigation: { id: 'inv-1', status: 'open' } } } });
    await expect(openInvestigation('row-1')).resolves.toEqual({ id: 'inv-1', status: 'open' });
    expect(client.post).toHaveBeenCalledWith('/platform/component_statuses/row-1/investigations');
  });

  it.each(['AlreadyOpen', 'DailyCapReached'])(
    'turns a 409 %s into a typed refusal carrying the token and the cap',
    async (token) => {
      client.post.mockRejectedValue({
        response: {
          status: 409,
          data: { success: false, error: 'refused', details: { refused: token, daily_cap: 20 } },
        },
      });

      const error = await openInvestigation('row-1').catch((e) => e);
      expect(error).toBeInstanceOf(InvestigationRefusedError);
      expect(error.refused).toBe(token);
      expect(error.dailyCap).toBe(20);
    }
  );

  it('a 409 that names no token carries null, not an invented one (C3p2 review R11)', async () => {
    client.post.mockRejectedValue({
      response: { status: 409, data: { success: false, error: 'refused for a reason not named' } },
    });

    const error = await openInvestigation('row-1').catch((e) => e);
    expect(error).toBeInstanceOf(InvestigationRefusedError);
    expect(error.refused).toBeNull();
    expect(error.message).toBe('refused for a reason not named');
  });

  it('rethrows anything that is NOT a 409 unchanged — a 500 is not a bound', async () => {
    const serverError = { response: { status: 500, data: { error: 'boom' } } };
    client.post.mockRejectedValue(serverError);

    const error = await openInvestigation('row-1').catch((e) => e);
    expect(error).not.toBeInstanceOf(InvestigationRefusedError);
    expect(error).toBe(serverError);
  });
});

describe('fetchRemediationRoute', () => {
  beforeEach(() => jest.clearAllMocks());

  it('defaults a MISSING `routed` to false, so a missing key reads unrouted by contract', async () => {
    client.get.mockResolvedValue({ data: { data: { component_status_id: 'row-1', signal_kind: null } } });
    await expect(fetchRemediationRoute('row-1')).resolves.toMatchObject({ routed: false });
  });

  it('keeps `routed: true` and the route when the server sends them', async () => {
    client.get.mockResolvedValue({
      data: { data: { component_status_id: 'row-1', routed: true, route: { lane_key: 'fleet_signal' } } },
    });
    await expect(fetchRemediationRoute('row-1')).resolves.toMatchObject({
      routed: true,
      route: { lane_key: 'fleet_signal' },
    });
  });

  it('does NOT treat a truthy non-boolean `routed` as routed', async () => {
    // The default is a strict `=== true`, so a stray "false" string or a 1 from
    // a misbehaving serializer cannot flip the panel into its routed branch.
    client.get.mockResolvedValue({ data: { data: { routed: 'false' } } });
    await expect(fetchRemediationRoute('row-1')).resolves.toMatchObject({ routed: false });
  });
});

describe('fetchComponentEvents', () => {
  beforeEach(() => jest.clearAllMocks());

  it('rejects a body with no events array — a malformed read is not an empty history (R2)', async () => {
    client.get.mockResolvedValue({ data: { data: { component_status_id: 'row-1' } } });
    await expect(fetchComponentEvents('row-1')).rejects.toThrow(/Malformed events response/);
  });

  it('resolves an EMPTY events array as an empty history', async () => {
    client.get.mockResolvedValue({
      data: {
        data: { component_status_id: 'row-1', events: [] },
        meta: { pagination: { current_page: 1, per_page: 20, total_count: 0, total_pages: 1 } },
      },
    });
    await expect(fetchComponentEvents('row-1')).resolves.toMatchObject({
      events: [],
      pagination: { total_count: 0 },
    });
  });
});

// C3p2 review R11: no fabricated defaults. A value the server did not send is
// unknown, and each of these used to become a number nobody measured.
describe('fetchInvestigations', () => {
  beforeEach(() => jest.clearAllMocks());

  it('keeps a MISSING daily cap null — never a cap of 0', async () => {
    client.get.mockResolvedValue({ data: { data: { component_status_id: 'row-1', open: [], recent: [] } } });
    const data = await fetchInvestigations('row-1');
    expect(data.daily_cap).toBeNull();
  });

  it('keeps the daily cap the server sent', async () => {
    client.get.mockResolvedValue({
      data: { data: { component_status_id: 'row-1', open: [], recent: [], daily_cap: 20 } },
    });
    expect((await fetchInvestigations('row-1')).daily_cap).toBe(20);
  });
});

describe('fetchComponentEvents — the total', () => {
  beforeEach(() => jest.clearAllMocks());

  const event = { id: 'e-1', from_verdict: 'ok', to_verdict: 'down', reason: null, occurred_at: '2026-09-10T12:00:00Z' };

  it('keeps a MISSING total null — the page length would claim there is nothing older', async () => {
    client.get.mockResolvedValue({ data: { data: { component_status_id: 'row-1', events: [event] }, meta: {} } });
    const result = await fetchComponentEvents('row-1');
    expect(result.events).toHaveLength(1);
    expect(result.pagination.total_count).toBeNull();
  });

  it('keeps the total the server sent', async () => {
    client.get.mockResolvedValue({
      data: {
        data: { component_status_id: 'row-1', events: [event] },
        meta: { pagination: { current_page: 1, per_page: 20, total_count: 57, total_pages: 3 } },
      },
    });
    expect((await fetchComponentEvents('row-1')).pagination.total_count).toBe(57);
  });
});
