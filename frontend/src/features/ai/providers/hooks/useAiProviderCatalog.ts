import { useEffect, useState } from 'react';
import { providersApi } from '@/shared/services/ai';
import type { AiProviderCatalog, AiProviderCatalogEntry } from '@/shared/types/ai';

const EMPTY: AiProviderCatalog = { items: [], known_capabilities: [] };

/**
 * Provider-type catalog (GET /ai/providers/catalog): the one source of the
 * per-type form defaults and of the capability names the backend accepts.
 * Without it (load failure) the forms stay manual.
 */
export const useAiProviderCatalog = (enabled = true) => {
  const [catalog, setCatalog] = useState<AiProviderCatalog>(EMPTY);

  useEffect(() => {
    if (!enabled) return;
    let cancelled = false;
    providersApi
      .getCatalog()
      .then((result) => {
        if (!cancelled) setCatalog(result);
      })
      .catch(() => {
        if (!cancelled) setCatalog(EMPTY);
      });
    return () => {
      cancelled = true;
    };
  }, [enabled]);

  const entryFor = (providerType: string): AiProviderCatalogEntry | undefined =>
    catalog.items.find((entry) => entry.provider_type === providerType);

  /** Capability options valid for a type: its catalog list, else every known name. */
  const capabilitiesFor = (providerType: string): string[] =>
    entryFor(providerType)?.capabilities ?? catalog.known_capabilities;

  return { catalog, entryFor, capabilitiesFor };
};
