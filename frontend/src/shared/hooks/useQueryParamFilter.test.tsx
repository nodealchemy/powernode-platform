import React from 'react';
import { renderHook, act } from '@testing-library/react';
import { MemoryRouter, useLocation } from 'react-router-dom';
import { useQueryParamFilter } from './useQueryParamFilter';

interface Filters {
  search: string;
  architectureId: string | null;
  status?: string | null;
}

const wrapperFor =
  (initialPath: string) =>
  ({ children }: { children: React.ReactNode }) =>
    <MemoryRouter initialEntries={[initialPath]}>{children}</MemoryRouter>;

const render = (path: string, map: Partial<Record<string, keyof Filters & string>>) =>
  renderHook(() => ({ f: useQueryParamFilter<Filters>(map), loc: useLocation() }), {
    wrapper: wrapperFor(path),
  });

describe('useQueryParamFilter', () => {
  it('seeds a present param into base filters and reports it active', () => {
    const { result } = render('/x?architecture=abc', { architecture: 'architectureId' });

    expect(result.current.f.hasActiveParamFilter).toBe(true);
    expect(result.current.f.activeParams).toEqual([
      { param: 'architecture', key: 'architectureId', value: 'abc' },
    ]);

    const base: Filters = { search: '', architectureId: null };
    expect(result.current.f.seedFilters(base)).toEqual({ search: '', architectureId: 'abc' });
  });

  it('returns base unchanged (same reference) and no active params when nothing matches', () => {
    const { result } = render('/x?other=ignored', { architecture: 'architectureId' });

    expect(result.current.f.hasActiveParamFilter).toBe(false);
    expect(result.current.f.activeParams).toEqual([]);

    const base: Filters = { search: '', architectureId: null };
    expect(result.current.f.seedFilters(base)).toBe(base);
  });

  it('reports only the mapped params present in the URL', () => {
    const { result } = render('/x?architecture=abc', {
      architecture: 'architectureId',
      status: 'status',
    });

    expect(result.current.f.activeParams).toEqual([
      { param: 'architecture', key: 'architectureId', value: 'abc' },
    ]);
  });

  it('clears mapped params from the URL while leaving unmapped params intact', () => {
    const { result } = render('/x?architecture=abc&keep=1', { architecture: 'architectureId' });

    expect(result.current.loc.search).toContain('architecture=abc');

    act(() => {
      result.current.f.clearParamFilters();
    });

    expect(result.current.loc.search).not.toContain('architecture');
    expect(result.current.loc.search).toContain('keep=1');
  });
});
