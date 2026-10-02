import { AxiosError, AxiosHeaders } from 'axios';
import { handleApiError, getIpBlockInfo, ErrorCodes } from './errorHandler';

const make = (status: number, data: unknown, headers: Record<string, string> = {}) => {
  const err = new AxiosError('failed', 'ERR_BAD_REQUEST');
  err.response = {
    status,
    data,
    statusText: '',
    headers: new AxiosHeaders(headers),
    config: { headers: new AxiosHeaders() },
  };
  return err;
};

describe('IP block (429 ip_blocked) handling', () => {
  it('reads the block from the body code and reports minutes', () => {
    const err = make(429, { code: 'ip_blocked', retry_after_seconds: 5400 }, { 'x-request-blocked': 'true' });
    expect(getIpBlockInfo(err)).toEqual({ retryAfterSeconds: 5400 });
    const api = handleApiError(err);
    expect(api.code).toBe(ErrorCodes.IP_BLOCKED);
    expect(api.message).toBe('This address is temporarily blocked, retry in 90 minutes.');
  });

  it('falls back to the header when the body is stripped', () => {
    const err = make(429, undefined, { 'x-request-blocked': 'true', 'retry-after': '30' });
    expect(handleApiError(err).message).toBe('This address is temporarily blocked, retry in 1 minute.');
  });

  it('leaves ordinary rate limiting alone', () => {
    const err = make(429, { error: 'Too many' });
    expect(getIpBlockInfo(err)).toBeNull();
    expect(handleApiError(err).code).toBe(ErrorCodes.RATE_LIMITED);
  });
});
