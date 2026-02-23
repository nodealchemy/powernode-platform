import React, { useState, useCallback, useEffect, useRef } from 'react';
import { Bot } from 'lucide-react';

export interface MentionMember {
  id: string;
  name: string;
  role: string;
  agent_type: string;
}

interface UseMentionAutocompleteOptions {
  members: MentionMember[];
  inputRef: React.RefObject<HTMLTextAreaElement | null>;
  value: string;
  onChange: (value: string) => void;
}

interface UseMentionAutocompleteReturn {
  showDropdown: boolean;
  filteredMembers: MentionMember[];
  selectedIndex: number;
  dropdownPosition: { top: number; left: number };
  handleKeyDown: (e: React.KeyboardEvent) => boolean;
  acceptMention: (member: MentionMember) => void;
  pendingMentions: MentionMember[];
  dismiss: () => void;
}

/**
 * Hook that manages @mention autocomplete state and text insertion.
 * Detects `@` trigger, filters members by prefix, and handles keyboard navigation.
 */
export function useMentionAutocomplete({
  members,
  inputRef,
  value,
  onChange,
}: UseMentionAutocompleteOptions): UseMentionAutocompleteReturn {
  const [showDropdown, setShowDropdown] = useState(false);
  const [selectedIndex, setSelectedIndex] = useState(0);
  const [searchTerm, setSearchTerm] = useState('');
  const [triggerStart, setTriggerStart] = useState(-1);
  const [dropdownPosition, setDropdownPosition] = useState({ top: 0, left: 0 });
  const [pendingMentions, setPendingMentions] = useState<MentionMember[]>([]);

  // Filter members by case-insensitive prefix match on search term
  const filteredMembers = members.filter(m =>
    m.name.toLowerCase().startsWith(searchTerm.toLowerCase())
  );

  // Detect @ trigger on value/cursor changes
  useEffect(() => {
    const input = inputRef.current;
    if (!input || members.length === 0) return;

    const cursorPos = input.selectionStart ?? 0;
    const textBeforeCursor = value.slice(0, cursorPos);

    // Find the last @ that could be a mention trigger
    const lastAt = textBeforeCursor.lastIndexOf('@');
    if (lastAt === -1) {
      setShowDropdown(false);
      return;
    }

    // @ must be at start or preceded by whitespace/newline
    const charBefore = lastAt > 0 ? textBeforeCursor[lastAt - 1] : ' ';
    if (charBefore !== ' ' && charBefore !== '\n' && lastAt !== 0) {
      setShowDropdown(false);
      return;
    }

    // Extract partial name text after @
    const partial = textBeforeCursor.slice(lastAt + 1);

    // Don't trigger if there's a space followed by more text after space
    // (means user finished typing the mention and moved on)
    // But DO allow spaces within agent names (e.g., "Technical Research")
    // Close if we hit a newline after @
    if (partial.includes('\n')) {
      setShowDropdown(false);
      return;
    }

    setSearchTerm(partial);
    setTriggerStart(lastAt);
    setSelectedIndex(0);

    // Position dropdown above the textarea
    setDropdownPosition({
      top: -(Math.min(members.length, 5) * 48 + 8), // approx height
      left: 0,
    });

    setShowDropdown(true);
  }, [value, members, inputRef]);

  // Accept a mention: replace @partial with @FullName
  const acceptMention = useCallback((member: MentionMember) => {
    const input = inputRef.current;
    if (!input || triggerStart === -1) return;

    const before = value.slice(0, triggerStart);
    const cursorPos = input.selectionStart ?? value.length;
    const after = value.slice(cursorPos);
    const mentionText = `@${member.name} `;

    const newValue = before + mentionText + after;
    onChange(newValue);

    // Track mention
    setPendingMentions(prev => {
      if (prev.some(m => m.id === member.id)) return prev;
      return [...prev, member];
    });

    // Restore cursor after insertion
    const newCursorPos = before.length + mentionText.length;
    setTimeout(() => {
      input.focus();
      input.setSelectionRange(newCursorPos, newCursorPos);
    }, 0);

    setShowDropdown(false);
    setSearchTerm('');
    setTriggerStart(-1);
  }, [value, onChange, triggerStart, inputRef]);

  // Delete an entire @mention token when backspace lands inside or at its end
  const handleMentionBackspace = useCallback((e: React.KeyboardEvent): boolean => {
    if (e.key !== 'Backspace' || pendingMentions.length === 0) return false;

    const input = inputRef.current;
    if (!input) return false;
    const cursor = input.selectionStart ?? 0;
    if (cursor === 0) return false;

    // Check each pending mention: does the cursor sit inside or right after @Name?
    for (const m of pendingMentions) {
      const token = `@${m.name}`;
      // Find all occurrences of this token
      let searchFrom = 0;
      while (searchFrom < value.length) {
        const idx = value.indexOf(token, searchFrom);
        if (idx === -1) break;
        const tokenEnd = idx + token.length;
        // Cursor is inside or at the trailing edge of this token
        if (cursor > idx && cursor <= tokenEnd) {
          e.preventDefault();
          const before = value.slice(0, idx);
          const after = value.slice(tokenEnd);
          onChange(before + after);
          // Remove from pending
          setPendingMentions(prev => prev.filter(p => p.id !== m.id));
          // Restore cursor to where the token started
          setTimeout(() => {
            input.focus();
            input.setSelectionRange(idx, idx);
          }, 0);
          return true;
        }
        searchFrom = tokenEnd;
      }
    }
    return false;
  }, [value, onChange, pendingMentions, inputRef]);

  // Keyboard handler — returns true if event was consumed
  const handleKeyDown = useCallback((e: React.KeyboardEvent): boolean => {
    // Backspace over a whole @mention
    if (handleMentionBackspace(e)) return true;

    if (!showDropdown || filteredMembers.length === 0) return false;

    switch (e.key) {
      case 'ArrowDown':
        e.preventDefault();
        setSelectedIndex(prev =>
          prev < filteredMembers.length - 1 ? prev + 1 : 0
        );
        return true;
      case 'ArrowUp':
        e.preventDefault();
        setSelectedIndex(prev =>
          prev > 0 ? prev - 1 : filteredMembers.length - 1
        );
        return true;
      case 'Tab':
      case 'Enter':
        e.preventDefault();
        acceptMention(filteredMembers[selectedIndex]);
        return true;
      case 'Escape':
        e.preventDefault();
        setShowDropdown(false);
        setTriggerStart(-1);
        return true;
      default:
        return false;
    }
  }, [showDropdown, filteredMembers, selectedIndex, acceptMention, handleMentionBackspace]);

  const dismiss = useCallback(() => {
    setShowDropdown(false);
    setTriggerStart(-1);
    setPendingMentions([]);
  }, []);

  // Clear pending mentions when value is cleared (message sent)
  useEffect(() => {
    if (value === '') {
      setPendingMentions([]);
    }
  }, [value]);

  return {
    showDropdown,
    filteredMembers,
    selectedIndex,
    dropdownPosition,
    handleKeyDown,
    acceptMention,
    pendingMentions,
    dismiss,
  };
}

// -- MentionDropdown component --

interface MentionDropdownProps {
  members: MentionMember[];
  selectedIndex: number;
  position: { top: number; left: number };
  onSelect: (member: MentionMember) => void;
}

function getRoleBadgeColor(role: string): string {
  switch (role) {
    case 'manager': return 'bg-theme-warning/15 text-theme-warning';
    case 'researcher': return 'bg-theme-info/15 text-theme-info';
    case 'writer': return 'bg-theme-success/15 text-theme-success';
    case 'executor': return 'bg-theme-interactive-primary/15 text-theme-interactive-primary';
    default: return 'bg-theme-hover text-theme-secondary';
  }
}

export const MentionDropdown: React.FC<MentionDropdownProps> = ({
  members,
  selectedIndex,
  position,
  onSelect,
}) => {
  const dropdownRef = useRef<HTMLDivElement>(null);

  // Scroll selected item into view
  useEffect(() => {
    if (dropdownRef.current) {
      const selectedEl = dropdownRef.current.children[selectedIndex] as HTMLElement;
      selectedEl?.scrollIntoView({ block: 'nearest' });
    }
  }, [selectedIndex]);

  if (members.length === 0) return null;

  return (
    <div
      ref={dropdownRef}
      className="absolute z-50 w-full max-h-60 overflow-y-auto bg-theme-surface border border-theme/40 rounded-xl shadow-lg backdrop-blur-sm"
      style={{ bottom: '100%', left: position.left, marginBottom: 4 }}
      data-testid="mention-dropdown"
    >
      {members.map((member, index) => (
        <button
          key={member.id}
          type="button"
          onClick={() => onSelect(member)}
          onMouseEnter={() => {/* selectedIndex is managed by hook */}}
          className={`w-full text-left px-3 py-2.5 transition-colors ${
            index === selectedIndex
              ? 'bg-theme-interactive-primary/10'
              : 'hover:bg-theme-hover'
          }`}
        >
          <div className="flex items-center gap-2.5">
            <Bot className="h-4 w-4 text-theme-tertiary flex-shrink-0" />
            <div className="flex-1 min-w-0">
              <span className="text-sm font-medium text-theme-primary truncate block">
                {member.name}
              </span>
            </div>
            <span className={`text-xs px-1.5 py-0.5 rounded-md ${getRoleBadgeColor(member.role)}`}>
              {member.role}
            </span>
            {member.agent_type === 'mcp_client' && (
              <span className="text-xs px-1.5 py-0.5 rounded-md bg-theme-interactive-primary/10 text-theme-interactive-primary">
                MCP
              </span>
            )}
          </div>
        </button>
      ))}
    </div>
  );
};
