import React from 'react';
import { FileText } from 'lucide-react';
import { Modal } from '@/shared/components/ui/Modal';
import { useEntityModal } from '@/shared/hooks/useEntityModal';
import { usePermissions } from '@/shared/hooks/usePermissions';
import { entityRegistry } from '@/shared/services/entityRegistry';
import { EntityDetailLoader } from './EntityDetailLoader';
import { EntityDetailModal } from './EntityDetailModal';

/**
 * Global host for cross-reference detail modals. Mounted ONCE in DashboardLayout
 * (system + every feature page render inside it). Reads `?entity=<type>&eid=<id>`
 * via `useEntityModal`, resolves the registered definition, and renders the right
 * surface using one of three modes:
 *   1. id modal     — bespoke modal self-fetches by id (NodeDetailModal, ...)
 *   2. object modal — fetch via `fetchById`, pass the object (sdwan/NetworkDetailModal)
 *   3. generic      — field-driven EntityDetailModal fallback
 */
export const EntityReferenceHost: React.FC = () => {
  const { entityType, entityId, isOpen, closeEntity } = useEntityModal();
  const { hasPermission } = usePermissions();

  if (!isOpen || !entityType || !entityId) return null;

  const def = entityRegistry.getEntity(entityType);
  if (!def) return null;
  if (def.permission && !hasPermission(def.permission)) return null;

  // Mode 1 — bespoke modal that takes an id prop and self-fetches.
  if (def.component && def.idProp) {
    const Component = def.component;
    const props: Record<string, unknown> = {
      [def.idProp]: entityId,
      isOpen: true,
      onClose: closeEntity,
    };
    return <Component {...props} />;
  }

  // Mode 2 — modal that takes a loaded object; fetch first, then render.
  if (def.component && def.objectProp && def.fetchById) {
    const Component = def.component;
    const objectProp = def.objectProp;
    const wrap = (node: React.ReactNode): React.ReactNode => (
      <Modal isOpen onClose={closeEntity} title={def.label} icon={<FileText className="w-6 h-6" />} maxWidth="2xl" variant="centered">
        {node}
      </Modal>
    );
    return (
      <EntityDetailLoader id={entityId} fetchById={def.fetchById} fallbackWrapper={wrap}>
        {(data) => {
          const props: Record<string, unknown> = {
            [objectProp]: data,
            isOpen: true,
            onClose: closeEntity,
          };
          return <Component {...props} />;
        }}
      </EntityDetailLoader>
    );
  }

  // Mode 3 — generic field-driven fallback.
  if (def.fetchById) {
    return <EntityDetailModal def={def} id={entityId} isOpen onClose={closeEntity} />;
  }

  return null;
};
