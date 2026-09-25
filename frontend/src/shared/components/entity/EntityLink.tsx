import React from 'react';
import { Link } from 'react-router-dom';
import { entityRegistry } from '@/shared/services/entityRegistry';
import { useEntityModal } from '@/shared/hooks/useEntityModal';
import { usePermissions } from '@/shared/hooks/usePermissions';
import { cn } from '@/shared/utils/cn';

interface EntityLinkProps {
  /** Registered entity type, e.g. "node_template". */
  type: string;
  /** Target id (may be composite for nested resources). */
  id?: string | null;
  /** Displayed text/content (falls back to the id). */
  label?: React.ReactNode;
  className?: string;
  /** Force plain-text rendering (e.g. when nested inside another interactive element). */
  disabled?: boolean;
}

/**
 * Reusable clickable reference. Opens the target object's detail surface: its
 * routed detail page for a `detailPath` type, otherwise the global
 * EntityReferenceHost. Degrades gracefully to plain text when the type is
 * not registered, the id is missing, or the viewer lacks the read permission —
 * so it is always safe to drop in place of a `<span>{name}</span>`.
 *
 * `stopPropagation` keeps row-level click handlers (expand/select) from firing.
 */
export const EntityLink: React.FC<EntityLinkProps> = ({ type, id, label, className, disabled }) => {
  const { openEntity, openByParam } = useEntityModal();
  const { hasPermission } = usePermissions();

  const def = entityRegistry.getEntity(type);
  const content = label ?? id ?? '';

  // Openable only if the registered type has a way to open (detail page,
  // legacy param, bespoke component, or a generic fetcher) and the read
  // permission is held.
  const canOpen =
    !disabled &&
    !!id &&
    !!def &&
    (!!def.detailPath || !!def.legacyParam || !!def.component || !!def.fetchById) &&
    (!def.permission || hasPermission(def.permission));

  if (!canOpen) {
    return <span className={cn('text-theme-secondary', className)}>{content}</span>;
  }

  const linkClassName = cn('text-theme-link hover:underline cursor-pointer text-left', className);
  const title = def?.label ? `View ${def.label}` : undefined;

  if (def && def.detailPath) {
    return (
      <Link
        to={def.detailPath(String(id))}
        onClick={(e) => e.stopPropagation()}
        className={linkClassName}
        title={title}
      >
        {content}
      </Link>
    );
  }

  return (
    <button
      type="button"
      onClick={(e) => {
        e.stopPropagation();
        if (def && def.legacyParam) {
          openByParam(def.legacyParam, String(id));
        } else {
          openEntity(type, String(id));
        }
      }}
      className={linkClassName}
      title={title}
    >
      {content}
    </button>
  );
};
