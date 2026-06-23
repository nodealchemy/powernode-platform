import { useCallback } from 'react';
import { useSearchParams } from 'react-router-dom';
import type { ContentScope } from './types';

const VALID_SCOPES: ContentScope[] = ['global', 'custom', 'all'];

function parseScope(raw: string | null, fallback: ContentScope): ContentScope {
  return (VALID_SCOPES as string[]).includes(raw ?? '') ? (raw as ContentScope) : fallback;
}

/**
 * Reads/writes the `?scope=` query param that the ScopeFilter drives and that
 * the list endpoints accept. Deep-linkable and shared across content pages.
 *
 * @param defaultScope selection when the URL has no (valid) `scope` param.
 *                     Defaults to `'all'` (global + the account's own copies).
 */
export function useScopeParam(
  defaultScope: ContentScope = 'all',
): [ContentScope, (scope: ContentScope) => void] {
  const [searchParams, setSearchParams] = useSearchParams();
  const scope = parseScope(searchParams.get('scope'), defaultScope);

  const setScope = useCallback(
    (next: ContentScope) => {
      setSearchParams(
        (prev) => {
          const params = new URLSearchParams(prev);
          if (next === defaultScope) {
            params.delete('scope');
          } else {
            params.set('scope', next);
          }
          return params;
        },
        { replace: true },
      );
    },
    [setSearchParams, defaultScope],
  );

  return [scope, setScope];
}

export default useScopeParam;
