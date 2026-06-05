import { useCallback } from 'react';
import { useSearchParams } from 'react-router-dom';

const ENTITY_PARAM = 'entity';
const ENTITY_ID_PARAM = 'eid';

/**
 * Generalized counterpart to `useAgentModal`: opens/closes the global
 * EntityReferenceHost via URL search params (`?entity=<type>&eid=<id>`).
 * Works from any page — the host is mounted once in DashboardLayout.
 *
 * Opening pushes a history entry so the browser back button closes the modal.
 * `id` may be composite (e.g. "networkId:ruleId") for nested resources — the
 * registered `fetchById` is responsible for parsing it.
 */
export function useEntityModal() {
  const [searchParams, setSearchParams] = useSearchParams();

  const entityType = searchParams.get(ENTITY_PARAM);
  const entityId = searchParams.get(ENTITY_ID_PARAM);
  const isOpen = entityType !== null && entityId !== null;

  const openEntity = useCallback(
    (type: string, id: string) => {
      setSearchParams((prev) => {
        const next = new URLSearchParams(prev);
        next.set(ENTITY_PARAM, type);
        next.set(ENTITY_ID_PARAM, id);
        return next;
      });
    },
    [setSearchParams],
  );

  const closeEntity = useCallback(() => {
    setSearchParams((prev) => {
      const next = new URLSearchParams(prev);
      next.delete(ENTITY_PARAM);
      next.delete(ENTITY_ID_PARAM);
      return next;
    });
  }, [setSearchParams]);

  // Open a legacy per-type modal that reads its own search param (e.g. `?agent=<id>`).
  // Used by EntityLink for types registered with a `legacyParam`.
  const openByParam = useCallback(
    (param: string, id: string) => {
      setSearchParams((prev) => {
        const next = new URLSearchParams(prev);
        next.set(param, id);
        return next;
      });
    },
    [setSearchParams],
  );

  return { entityType, entityId, isOpen, openEntity, closeEntity, openByParam } as const;
}
