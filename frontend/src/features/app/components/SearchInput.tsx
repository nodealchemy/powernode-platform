/**
 * Marketplace Search Input
 *
 * Debounced search input with icon for filtering marketplace items.
 */

import React, { useState, useEffect, useCallback } from 'react';
import { Search } from 'lucide-react';
import { Input } from '@/shared/components/ui/Input';

interface SearchInputProps {
  value: string;
  onChange: (value: string) => void;
  placeholder?: string;
  debounceMs?: number;
}

export const SearchInput: React.FC<SearchInputProps> = ({
  value,
  onChange,
  placeholder = 'Search marketplace...',
  debounceMs = 300
}) => {
  const [localValue, setLocalValue] = useState(value);

  // Sync local value with prop value
  useEffect(() => {
    setLocalValue(value);
  }, [value]);

  // Debounced onChange
  useEffect(() => {
    const timeoutId = setTimeout(() => {
      if (localValue !== value) {
        onChange(localValue);
      }
    }, debounceMs);

    return () => clearTimeout(timeoutId);
  }, [localValue, value, onChange, debounceMs]);

  const handleChange = useCallback((e: React.ChangeEvent<HTMLInputElement>) => {
    setLocalValue(e.target.value);
  }, []);

  return (
    <div className="relative w-full search-container">
      <div className="absolute left-3 top-1/2 transform -translate-y-1/2 text-theme-tertiary">
        <Search className="h-4 w-4" />
      </div>
      <Input
        type="search"
        value={localValue}
        onChange={handleChange}
        placeholder={placeholder}
        className="pl-10 w-full"
        data-testid="search-input"
      />
    </div>
  );
};
