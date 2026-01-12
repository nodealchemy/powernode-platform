
// Removed unused Button and FormField imports

// Reusable Toggle Switch Component
interface ToggleSwitchProps {
  checked: boolean;
  onChange: (checked: boolean) => void;
  disabled?: boolean;
  variant?: 'success' | 'warning' | 'error' | 'primary';
  size?: 'sm' | 'md';
}

export const ToggleSwitch: React.FC<ToggleSwitchProps> = ({
  checked,
  onChange,
  disabled = false,
  variant = 'success',
  size = 'md'
}) => {
  const getVariantClass = () => {
    switch (variant) {
      case 'success': return 'bg-theme-success';
      case 'warning': return 'bg-theme-warning';
      case 'error': return 'bg-theme-error';
      case 'primary': return 'bg-theme-interactive-primary';
      default: return 'bg-theme-success';
    }
  };

  const sizeClasses = size === 'sm' 
    ? { track: 'w-9 h-5', thumb: 'h-3 w-3', translateChecked: 'translate-x-4', translateUnchecked: 'translate-x-0.5' }
    : { track: 'w-11 h-6', thumb: 'h-4 w-4', translateChecked: 'translate-x-6', translateUnchecked: 'translate-x-1' };

  return (
    <button 
      disabled={disabled} 
      type="button" 
      onClick={() => !disabled && onChange(!checked)}
      className={`relative inline-flex ${sizeClasses.track} items-center rounded-full transition-colors duration-200 ease-in-out focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-offset-theme-background ${
        disabled 
          ? 'opacity-50 cursor-not-allowed' 
          : 'cursor-pointer'
      } ${
        checked 
          ? getVariantClass()
          : 'bg-theme-surface-secondary border border-theme'
      } focus:ring-${variant === 'primary' ? 'theme-interactive-primary' : `theme-${variant}`}`}
    >
      <span
        className={`inline-block ${sizeClasses.thumb} transform rounded-full bg-theme-background shadow-lg transition-transform duration-200 ease-in-out ${
          checked ? sizeClasses.translateChecked : sizeClasses.translateUnchecked
        }`}
      />
    </button>
  );
};

// Settings Card Component
interface SettingsCardProps {
  title: string;
  description?: string;
  icon?: string;
  children: React.ReactNode;
  className?: string;
}

export const SettingsCard: React.FC<SettingsCardProps> = ({
  title,
  description,
  icon,
  children,
  className = ''
}) => {
  return (
    <div className={`card-theme ${className}`}>
      <div className="px-6 py-4 border-b border-theme">
        <h3 className="text-lg font-semibold text-theme-primary flex items-center">
          {icon && <span className="mr-2">{icon}</span>}
          {title}
        </h3>
        {description && (
          <p className="text-sm text-theme-secondary mt-1">{description}</p>
        )}
      </div>
      <div className="p-6">
        {children}
      </div>
    </div>
  );
};

// Toggle Setting Item Component
interface ToggleSettingItemProps {
  title: string;
  description: string;
  checked: boolean;
  onChange: (checked: boolean) => void;
  disabled?: boolean;
  variant?: 'success' | 'warning' | 'error' | 'primary';
  className?: string;
}

export const ToggleSettingItem: React.FC<ToggleSettingItemProps> = ({
  title,
  description,
  checked,
  onChange,
  disabled = false,
  variant = 'success',
  className = ''
}) => {
  return (
    <div className={`flex items-center justify-between p-4 rounded-lg border border-theme bg-theme-background-secondary ${className}`}>
      <div>
        <h4 className="text-sm font-medium text-theme-primary">{title}</h4>
        <p className="text-sm text-theme-secondary">{description}</p>
      </div>
      <ToggleSwitch
        checked={checked}
        onChange={onChange}
        disabled={disabled}
        variant={variant}
      />
    </div>
  );
};

// Form Field Component
// Input Component
interface InputProps extends React.InputHTMLAttributes<HTMLInputElement> {
  error?: boolean;
}

export const Input: React.FC<InputProps> = ({
  error = false,
  className = '',
  ...props
}) => {
  const errorClass = error ? 'border-theme-error focus:border-theme-error' : '';
  return (
    <input
      className={`input-theme ${errorClass} ${className}`}
      {...props}
    />
  );
};

// Select Component
interface SelectProps extends React.SelectHTMLAttributes<HTMLSelectElement> {
  error?: boolean;
  children: React.ReactNode;
}

export const Select: React.FC<SelectProps> = ({
  error = false,
  className = '',
  children,
  ...props
}) => {
  const errorClass = error ? 'border-theme-error focus:border-theme-error' : '';
  return (
    <select
      className={`select-theme ${errorClass} ${className}`}
      {...props}
    >
      {children}
    </select>
  );
};

// Stats Grid Component
interface StatsCardProps {
  icon: string;
  title: string;
  value: string | number;
  valueColor?: 'primary' | 'success' | 'warning' | 'error' | 'info';
}

export const StatsCard: React.FC<StatsCardProps> = ({
  icon,
  title,
  value,
  valueColor = 'primary'
}) => {
  const getValueColorClass = () => {
    switch (valueColor) {
      case 'success': return 'text-theme-success';
      case 'warning': return 'text-theme-warning';
      case 'error': return 'text-theme-error';
      case 'info': return 'text-theme-info';
      default: return 'text-theme-primary';
    }
  };

  return (
    <div className="card-theme p-4">
      <div className="flex items-center">
        <div className="text-2xl mr-3">{icon}</div>
        <div>
          <p className="text-sm text-theme-secondary">{title}</p>
          <p className={`text-xl font-semibold ${getValueColorClass()}`}>
            {value}
          </p>
        </div>
      </div>
    </div>
  );
};

// Section Header Component
interface SectionHeaderProps {
  title: string;
  description?: string;
  action?: React.ReactNode;
  className?: string;
}

export const SectionHeader: React.FC<SectionHeaderProps> = ({
  title,
  description,
  action,
  className = ''
}) => {
  return (
    <div className={`flex justify-between items-center ${className}`}>
      <div>
        <h4 className="text-md font-semibold text-theme-primary">{title}</h4>
        {description && (
          <p className="text-sm text-theme-secondary mt-1">{description}</p>
        )}
      </div>
      {action && <div>{action}</div>}
    </div>
  );
};