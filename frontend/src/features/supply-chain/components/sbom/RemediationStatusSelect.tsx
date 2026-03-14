import React from 'react';

type RemediationStatus = 'open' | 'in_progress' | 'fixed' | 'wont_fix';

interface RemediationStatusSelectProps {
  value: RemediationStatus;
  onChange: (status: RemediationStatus) => void;
  disabled?: boolean;
  size?: 'sm' | 'md';
}

const statusStyles: Record<RemediationStatus, string> = {
  open: 'bg-theme-error/10 text-theme-error border-theme-error/30',
  in_progress: 'bg-theme-warning/10 text-theme-warning border-theme-warning/30',
  fixed: 'bg-theme-success/10 text-theme-success border-theme-success/30',
  wont_fix: 'bg-theme-muted/10 text-theme-secondary border-theme-border',
};

const statusLabels: Record<RemediationStatus, string> = {
  open: 'Open',
  in_progress: 'In Progress',
  fixed: 'Fixed',
  wont_fix: "Won't Fix",
};

export const RemediationStatusSelect: React.FC<RemediationStatusSelectProps> = ({
  value,
  onChange,
  disabled = false,
  size = 'sm',
}) => {
  const sizeClasses = size === 'sm' ? 'text-xs px-2 py-1' : 'text-sm px-3 py-2';

  return (
    <select
      value={value}
      onChange={(e) => onChange(e.target.value as RemediationStatus)}
      disabled={disabled}
      className={`
        rounded-md border font-medium cursor-pointer
        focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary
        disabled:opacity-50 disabled:cursor-not-allowed
        ${sizeClasses}
        ${statusStyles[value]}
      `}
    >
      {Object.entries(statusLabels).map(([status, label]) => (
        <option key={status} value={status}>
          {label}
        </option>
      ))}
    </select>
  );
};
