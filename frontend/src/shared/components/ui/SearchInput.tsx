import React from 'react';
import { Search, X } from 'lucide-react';

export interface SearchInputProps {
  value: string;
  onChange: (value: string) => void;
  placeholder?: string;
  className?: string;
  disabled?: boolean;
}

export const SearchInput: React.FC<SearchInputProps> = ({
  value,
  onChange,
  placeholder = 'Search...',
  className = '',
  disabled = false
}) => {
  const handleClear = () => {
    onChange('');
  };

  return (
    <div className={`relative ${className}`}>
      <div className="absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none">
        <Search className="h-4 w-4 text-theme-tertiary" />
      </div>
      <input
        type="text"
        value={value}
        onChange={(e) => onChange(e.target.value)}
        placeholder={placeholder}
        disabled={disabled}
        className={`
          w-full pl-10 pr-10 py-2 border border-theme-border rounded-md 
          bg-theme-surface text-theme-primary 
          placeholder-theme-tertiary 
          focus:outline-none focus:ring-2 focus:ring-theme-primary focus:border-transparent
          ${disabled ? 'opacity-50 cursor-not-allowed' : ''}
        `.replace(/\s+/g, ' ').trim()}
      />
      {value && !disabled && (
        <button
          type="button"
          onClick={handleClear}
          className="absolute inset-y-0 right-0 pr-3 flex items-center hover:text-theme-primary text-theme-tertiary"
          aria-label="Clear search"
        >
          <X className="h-4 w-4" />
        </button>
      )}
    </div>
  );
};