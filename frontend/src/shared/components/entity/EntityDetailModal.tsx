import React from 'react';
import { Modal } from '@/shared/components/ui/Modal';
import { entityRegistry, type EntityDefinition } from '@/shared/services/entityRegistry';
import { EntityDetailLoader } from './EntityDetailLoader';
import { EntityLink } from './EntityLink';

/** Keys that are noise in a generic field dump. */
const HIDDEN_KEYS = new Set(['id', 'account_id', 'type']);

function humanize(key: string): string {
  return key.replace(/_/g, ' ').replace(/\b\w/g, (c) => c.toUpperCase());
}

function isScalar(value: unknown): value is string | number | boolean {
  return typeof value === 'string' || typeof value === 'number' || typeof value === 'boolean';
}

interface RenderedField {
  key: string;
  label: string;
  node: React.ReactNode;
}

interface EntityDetailModalProps {
  def: EntityDefinition;
  id: string;
  isOpen: boolean;
  onClose: () => void;
}

/**
 * Generic, field-driven detail modal — the fallback cross-reference target for
 * types that have a `fetchById` but no bespoke modal. Renders the object's own
 * scalar fields; fields configured with `refType` render as nested EntityLinks.
 * Rich tabbed detail stays in the bespoke modals; this gives consistent baseline
 * coverage for the ~20 types that lack one without hand-building 20 components.
 */
export const EntityDetailModal: React.FC<EntityDetailModalProps> = ({ def, id, isOpen, onClose }) => {
  const fetchById = def.fetchById;
  if (!fetchById) return null;

  return (
    <Modal isOpen={isOpen} onClose={onClose} title={def.label} maxWidth="2xl" variant="centered">
      <EntityDetailLoader id={isOpen ? id : null} fetchById={fetchById}>
        {(data) => {
          const obj = (data ?? {}) as Record<string, unknown>;
          const title =
            def.labelField && isScalar(obj[def.labelField]) ? String(obj[def.labelField]) : def.label;

          const fields: RenderedField[] = [];
          const push = (
            key: string,
            value: unknown,
            label?: string,
            refType?: string,
            refIdKey?: string,
          ): void => {
            if (value === null || value === undefined || value === '') return;
            let node: React.ReactNode;
            if (refType && entityRegistry.hasEntity(refType)) {
              const refId = String(obj[refIdKey ?? key] ?? value);
              node = <EntityLink type={refType} id={refId} label={String(value)} />;
            } else if (isScalar(value)) {
              node = <span className="text-theme-primary break-words">{String(value)}</span>;
            } else {
              return; // skip nested objects/arrays in the generic view
            }
            fields.push({ key, label: label ?? humanize(key), node });
          };

          if (def.fields) {
            def.fields.forEach((f) => push(f.key, obj[f.key], f.label, f.refType, f.refIdKey));
          } else {
            Object.keys(obj)
              .filter((k) => !HIDDEN_KEYS.has(k) && isScalar(obj[k]))
              .forEach((k) => push(k, obj[k]));
          }

          return (
            <div className="space-y-4">
              <h2 className="text-lg font-semibold text-theme-primary">{title}</h2>
              {fields.length === 0 ? (
                <p className="text-sm text-theme-secondary">No additional details available.</p>
              ) : (
                <div className="grid grid-cols-2 md:grid-cols-3 gap-3 text-sm">
                  {fields.map((f) => (
                    <div key={f.key}>
                      <label className="block text-xs font-semibold text-theme-secondary uppercase tracking-wide mb-1">
                        {f.label}
                      </label>
                      {f.node}
                    </div>
                  ))}
                </div>
              )}
            </div>
          );
        }}
      </EntityDetailLoader>
    </Modal>
  );
};
