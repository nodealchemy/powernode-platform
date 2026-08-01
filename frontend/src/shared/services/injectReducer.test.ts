import { createSlice } from '@reduxjs/toolkit';
import { store, injectReducer, injectedReducerKeys } from '@/shared/services';

// The extension state seam. Extensions compose routes/nav/channels through
// featureRegistry; before this existed there was no equivalent for Redux state,
// so an extension could define a slice with nowhere to register its reducer —
// which is exactly what one shipped, undetected, because nothing rendered the
// components that would have thrown.

const makeSlice = (name: string, initial: { value: number }) =>
  createSlice({
    name,
    initialState: initial,
    reducers: {
      bump: (state) => {
        state.value += 1;
      },
    },
  });

describe('injectReducer (extension state seam)', () => {
  it('makes an extension slice readable from the shared store', () => {
    const slice = makeSlice('ext_alpha', { value: 1 });

    expect((store.getState() as Record<string, unknown>).ext_alpha).toBeUndefined();

    injectReducer('ext_alpha', slice.reducer);

    expect((store.getState() as Record<string, unknown>).ext_alpha).toEqual({ value: 1 });
    expect(injectedReducerKeys()).toContain('ext_alpha');
  });

  it('keeps core slices intact across an injection', () => {
    const before = store.getState().auth;

    injectReducer('ext_beta', makeSlice('ext_beta', { value: 0 }).reducer);

    // replaceReducer must rebuild from the static core map, not replace it —
    // a seam that dropped auth would log every user out on extension load.
    expect(store.getState().auth).toEqual(before);
    expect(store.getState().ui).toBeDefined();
    expect(store.getState().config).toBeDefined();
  });

  it('preserves already-injected slice state when a later extension registers', () => {
    injectReducer('ext_gamma', makeSlice('ext_gamma', { value: 5 }).reducer);
    store.dispatch({ type: 'ext_gamma/bump' });
    expect((store.getState() as Record<string, unknown>).ext_gamma).toEqual({ value: 6 });

    // A runtime extension can register AFTER first render (index.tsx renders
    // anyway on boot-timeout), so a later injection must not reset earlier state.
    injectReducer('ext_delta', makeSlice('ext_delta', { value: 0 }).reducer);

    expect((store.getState() as Record<string, unknown>).ext_gamma).toEqual({ value: 6 });
  });

  it('is idempotent — re-registering a key does not clobber live state', () => {
    const slice = makeSlice('ext_epsilon', { value: 0 });
    injectReducer('ext_epsilon', slice.reducer);
    store.dispatch({ type: 'ext_epsilon/bump' });
    expect((store.getState() as Record<string, unknown>).ext_epsilon).toEqual({ value: 1 });

    // HMR and a double-invoked register() both re-enter this path; resetting
    // to initialState there would silently discard user state mid-session.
    injectReducer('ext_epsilon', makeSlice('ext_epsilon', { value: 99 }).reducer);

    expect((store.getState() as Record<string, unknown>).ext_epsilon).toEqual({ value: 1 });
    expect(injectedReducerKeys().filter((k) => k === 'ext_epsilon')).toHaveLength(1);
  });

  it('dispatches extension actions through the shared store', () => {
    injectReducer('ext_zeta', makeSlice('ext_zeta', { value: 10 }).reducer);

    store.dispatch({ type: 'ext_zeta/bump' });

    expect((store.getState() as Record<string, unknown>).ext_zeta).toEqual({ value: 11 });
  });
});
