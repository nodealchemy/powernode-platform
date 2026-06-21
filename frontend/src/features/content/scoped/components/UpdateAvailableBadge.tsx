import React from 'react';
import { ArrowDownToLine } from 'lucide-react';

interface UpdateAvailableBadgeProps {
  /** Optional click handler (e.g. open the update-from-source modal). */
  onClick?: () => void;
  className?: string;
}

/**
 * Subtle "Update available from baseline" indicator for an account copy whose
 * origin has diverged (preview returned `synced: false`). Renders as a button
 * when `onClick` is provided, otherwise a static badge.
 */
export const UpdateAvailableBadge: React.FC<UpdateAvailableBadgeProps> = ({ onClick, className = '' }) => {
  const content = (
    <>
      <ArrowDownToLine className="w-3 h-3" />
      <span>Update available from baseline</span>
    </>
  );

  const base =
    'inline-flex items-center gap-1 px-2 py-0.5 text-xs rounded-full bg-theme-info-bg text-theme-info-fg';

  if (onClick) {
    return (
      <button
        type="button"
        onClick={(e) => {
          e.stopPropagation();
          onClick();
        }}
        className={`${base} hover:opacity-80 transition-opacity ${className}`}
        title="Review and apply updates from the platform baseline"
      >
        {content}
      </button>
    );
  }

  return <span className={`${base} ${className}`}>{content}</span>;
};

export default UpdateAvailableBadge;
