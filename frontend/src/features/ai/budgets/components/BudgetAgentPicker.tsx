import React, { useEffect, useMemo, useState } from 'react';
import { useBudgetAgentOptions } from '../api/budgetsApi';

interface BudgetAgentPickerProps {
  /** Accessible name of the select ("Agent", "Child agent"). */
  label: string;
  value: string;
  onChange: (agentId: string) => void;
  /** An agent that may not be picked (a budget's own agent, when allocating from it). */
  excludeId?: string;
  enabled?: boolean;
  selectClassName: string;
  searchClassName: string;
}

const SEARCH_DEBOUNCE_MS = 250;

/**
 * The agent a budget is created or allocated for. The options are one page of
 * the agents endpoint (100); a name search re-queries that endpoint, so an
 * account with more agents than that still reaches every one. The chosen agent
 * stays selectable while a search that does not match it is showing.
 */
export const BudgetAgentPicker: React.FC<BudgetAgentPickerProps> = ({
  label, value, onChange, excludeId, enabled = true, selectClassName, searchClassName,
}) => {
  const [searchInput, setSearchInput] = useState('');
  const [search, setSearch] = useState('');
  const [chosen, setChosen] = useState<{ id: string; name: string } | null>(null);
  const { data: agents } = useBudgetAgentOptions(search, enabled);

  useEffect(() => {
    const timer = setTimeout(() => setSearch(searchInput.trim()), SEARCH_DEBOUNCE_MS);
    return () => clearTimeout(timer);
  }, [searchInput]);

  const options = useMemo(() => {
    const listed = (agents ?? []).filter((agent) => agent.id !== excludeId);
    return chosen && chosen.id === value && !listed.some((agent) => agent.id === chosen.id)
      ? [chosen, ...listed]
      : listed;
  }, [agents, excludeId, chosen, value]);

  const handleSelect = (agentId: string) => {
    setChosen(options.find((agent) => agent.id === agentId) ?? null);
    onChange(agentId);
  };

  return (
    <div className="flex flex-col gap-1">
      <input
        type="search"
        aria-label="Search agents"
        placeholder="Search agents…"
        value={searchInput}
        onChange={(e) => setSearchInput(e.target.value)}
        // Enter narrows the list; it must not submit the form the picker sits in.
        onKeyDown={(e) => { if (e.key === 'Enter') e.preventDefault(); }}
        className={searchClassName}
      />
      <select
        id={`budget-agent-${label.toLowerCase().replace(/\s+/g, '-')}`}
        aria-label={label}
        value={value}
        onChange={(e) => handleSelect(e.target.value)}
        className={selectClassName}
        required
      >
        <option value="">Select agent…</option>
        {options.map((agent) => <option key={agent.id} value={agent.id}>{agent.name}</option>)}
      </select>
    </div>
  );
};
