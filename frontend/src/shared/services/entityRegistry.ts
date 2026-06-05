import type { ComponentType } from 'react';

/**
 * Cross-reference field config for the generic field-driven EntityDetailModal.
 * When `refType` is set and that type is registered, the field renders as a
 * nested <EntityLink> instead of plain text.
 */
export interface EntityFieldConfig {
  key: string;
  label?: string;
  /** Render this field's value as a link to another entity of this type. */
  refType?: string;
  /** Where to read the referenced id from (defaults to `key`). */
  refIdKey?: string;
}

/**
 * One object type's cross-reference definition. The host (`EntityReferenceHost`)
 * picks a render mode from the fields present:
 *  - id modal:     `component` + `idProp`                  → modal self-fetches by id
 *  - object modal: `component` + `objectProp` + `fetchById`→ host fetches, passes the object
 *  - generic:      `fetchById` only                        → host renders the generic EntityDetailModal
 *
 * Mirrors the owner-keyed shape of `featureRegistry`: extensions register their
 * own types, core stays ignorant of them.
 */
export interface EntityDefinition {
  type: string;
  /** Human label for the type, e.g. "Template". */
  label: string;
  /** Read permission required to open the detail surface (degrades to plain text if absent). */
  permission?: string;
  /** lucide-react icon name (optional, used by the generic modal header). */
  icon?: string;
  /**
   * For types backed by a pre-existing global modal driven by its OWN url search
   * param (e.g. core's agent/team/mission modals read `?agent=`/`?team=`/`?mission=`
   * and are mounted separately from EntityReferenceHost). Set the param name and
   * EntityLink opens that legacy modal directly — reusing the rich existing modal
   * instead of the generic field view. Takes precedence over component/fetchById.
   */
  legacyParam?: string;
  /** A detail modal component (bespoke or wrapper). */
  component?: ComponentType<Record<string, unknown>>;
  /** If set, the id is passed to `component` under this prop (modal self-fetches by id). */
  idProp?: string;
  /** If set, the fetched object is passed to `component` under this prop. */
  objectProp?: string;
  /** Fetch the object by the EntityLink id (id may be composite, e.g. "networkId:ruleId"). */
  fetchById?: (id: string) => Promise<unknown>;
  /** For the generic modal: which field holds the display title. */
  labelField?: string;
  /** For the generic modal: explicit field list (falls back to all scalar fields). */
  fields?: EntityFieldConfig[];
}

interface EntityRegistryState {
  /** owner → its registered definitions (for introspection / teardown) */
  byOwner: Map<string, EntityDefinition[]>;
  /** type → definition (last registration wins) */
  byType: Map<string, EntityDefinition>;
  version: number;
  listeners: Set<() => void>;
}

const state: EntityRegistryState = {
  byOwner: new Map(),
  byType: new Map(),
  version: 0,
  listeners: new Set(),
};

function notify(): void {
  state.version += 1;
  state.listeners.forEach((listener) => listener());
}

/**
 * Singleton entity-reference registry. Mirrors `featureRegistry`'s shape so the
 * mental model is identical: `registerEntities(owner, defs)` at startup, then
 * `<EntityLink>` / `<EntityReferenceHost>` resolve a type via `getEntity(type)`.
 */
export const entityRegistry = {
  registerEntities(owner: string, defs: EntityDefinition[]): void {
    const existing = state.byOwner.get(owner) ?? [];
    state.byOwner.set(owner, [...existing, ...defs]);
    defs.forEach((def) => state.byType.set(def.type, def));
    notify();
  },
  getEntities(owner?: string): EntityDefinition[] {
    if (owner) return state.byOwner.get(owner) ?? [];
    return Array.from(state.byType.values());
  },
  getEntity(type: string): EntityDefinition | undefined {
    return state.byType.get(type);
  },
  hasEntity(type: string): boolean {
    return state.byType.has(type);
  },
  getRegisteredOwners(): string[] {
    return Array.from(state.byOwner.keys());
  },
  getVersion(): number {
    return state.version;
  },
  subscribe(listener: () => void): () => void {
    state.listeners.add(listener);
    return () => {
      state.listeners.delete(listener);
    };
  },
  clear(): void {
    state.byOwner.clear();
    state.byType.clear();
    notify();
  },
};
