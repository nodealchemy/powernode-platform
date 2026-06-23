import React, { useState } from 'react';
import { Copy } from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import type { ButtonProps } from '@/shared/components/ui/Button';
import { useNotifications } from '@/shared/hooks/useNotifications';

interface CloneToCustomizeButtonProps {
  /** The clone API call (e.g. `() => skillsApi.clone(skill.id)`). Returns the new copy. */
  onClone: () => Promise<unknown>;
  /** Called with the freshly-created editable copy on success. */
  onCloned?: (copy: unknown) => void;
  /** Whether the user is allowed to create content (hide the CTA otherwise). */
  canClone?: boolean;
  label?: string;
  size?: ButtonProps['size'];
  variant?: ButtonProps['variant'];
  className?: string;
}

/**
 * "Clone to customize" action for GLOBAL (read-only) foundational content.
 * Forks the platform item into the account as an editable copy, then hands the
 * copy back so the caller can navigate to / refresh it.
 */
export const CloneToCustomizeButton: React.FC<CloneToCustomizeButtonProps> = ({
  onClone,
  onCloned,
  canClone = true,
  label = 'Clone to customize',
  size = 'sm',
  variant = 'secondary',
  className = '',
}) => {
  const { showNotification } = useNotifications();
  const [cloning, setCloning] = useState(false);

  if (!canClone) return null;

  const handleClick = async (e: React.MouseEvent) => {
    e.stopPropagation();
    if (cloning) return;
    setCloning(true);
    try {
      const copy = await onClone();
      showNotification('Cloned to an editable copy', 'success');
      onCloned?.(copy);
    } catch {
      showNotification('Failed to clone item', 'error');
    } finally {
      setCloning(false);
    }
  };

  return (
    <Button
      type="button"
      variant={variant}
      size={size}
      loading={cloning}
      onClick={handleClick}
      className={className}
    >
      <Copy className="w-4 h-4 mr-1" />
      {label}
    </Button>
  );
};

export default CloneToCustomizeButton;
