import React from 'react';
import { useNavigate } from 'react-router-dom';

export interface TabButtonProps {
  id: string;
  label: string;
  icon?: string;
  path: string;
  isActive: boolean;
  onClick?: () => void;
  className?: string;
  disabled?: boolean;
}

export const TabButton: React.FC<TabButtonProps> = ({
  id: _id,
  label,
  icon,
  path,
  isActive,
  onClick,
  className = '',
  disabled = false
}) => {
  const navigate = useNavigate();

  const handleClick = () => {
    if (disabled) return;
    
    if (onClick) {
      onClick();
    } else {
      navigate(path);
    }
  };

  return (
    <button
      type="button"
      onClick={handleClick}
      disabled={disabled}
      className={`
        flex items-center space-x-2 py-2 px-1 border-b-2 font-medium text-sm whitespace-nowrap transition-colors
        ${isActive
          ? 'border-theme-link text-theme-link'
          : 'border-transparent text-theme-secondary hover:text-theme-primary hover:border-theme'
        }
        ${disabled ? 'opacity-50 cursor-not-allowed' : 'cursor-pointer'}
        ${className}
      `.trim()}
    >
      {icon && <span className="text-base">{icon}</span>}
      <span>{label}</span>
    </button>
  );
};

export default TabButton;