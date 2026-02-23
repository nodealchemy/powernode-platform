import React, { useRef, useCallback, useEffect } from 'react';
import { ArrowUp, Loader2 } from 'lucide-react';
import { useMentionAutocomplete, MentionDropdown } from './MentionAutocomplete';
import type { MentionMember } from './MentionAutocomplete';
import { parseMentions } from './utils';

interface MessageComposerProps {
  value: string;
  onChange: (value: string) => void;
  onSend: () => void;
  onTyping: () => void;
  sending: boolean;
  members?: MentionMember[];
  onMentionsChange?: (mentions: Array<{ id: string; name: string }>) => void;
}

/**
 * Font metrics shared between textarea and highlight backdrop.
 * Textareas default to monospace — forcing `inherit` keeps them aligned.
 */
const mirrorStyle: React.CSSProperties = {
  fontFamily: 'inherit',
  fontSize: '0.875rem',
  lineHeight: '1.25rem',
  letterSpacing: 'normal',
  wordSpacing: 'normal',
  boxSizing: 'border-box',
};

export const MessageComposer = React.memo<MessageComposerProps>(({
  value,
  onChange,
  onSend,
  onTyping,
  sending,
  members,
  onMentionsChange
}) => {
  const inputRef = useRef<HTMLTextAreaElement>(null);
  const backdropRef = useRef<HTMLDivElement>(null);

  const mention = useMentionAutocomplete({
    members: members || [],
    inputRef,
    value,
    onChange,
  });

  useEffect(() => {
    onMentionsChange?.(
      mention.pendingMentions.map(m => ({ id: m.id, name: m.name }))
    );
  }, [mention.pendingMentions, onMentionsChange]);

  const mentionNames = mention.pendingMentions.map(m => m.name);
  const hasMentionHighlights = mentionNames.length > 0 && mentionNames.some(n => value.includes(`@${n}`));
  const canSend = value.trim().length > 0 && !sending;

  const handleInputChange = useCallback((e: React.ChangeEvent<HTMLTextAreaElement>) => {
    onChange(e.target.value);
    onTyping();
  }, [onChange, onTyping]);

  const handleKeyDown = useCallback((e: React.KeyboardEvent) => {
    if (mention.handleKeyDown(e)) return;

    // Enter sends, Shift+Enter and Ctrl+Enter insert newlines
    if (e.key === 'Enter' && !e.shiftKey && !e.ctrlKey) {
      e.preventDefault();
      onSend();
    }
  }, [onSend, mention.handleKeyDown]);

  const handleScroll = useCallback(() => {
    if (backdropRef.current && inputRef.current) {
      backdropRef.current.scrollTop = inputRef.current.scrollTop;
    }
  }, []);

  /**
   * Render backdrop content: text is transparent, only mention backgrounds
   * are visible. The real textarea text sits on top, fully visible.
   */
  const renderHighlightBackdrop = (): React.ReactNode => {
    if (!value) return '\u00A0';
    const parts = parseMentions(value, mentionNames);
    if (parts.length === 1 && parts[0].type === 'text') return value;
    return parts.map((part, i) =>
      part.type === 'mention'
        ? <span key={i} className="bg-theme-interactive-primary/20 rounded-sm px-0.5">{part.value}</span>
        : <React.Fragment key={i}>{part.value}</React.Fragment>
    );
  };

  return (
    <div className="px-4 py-3 border-t border-theme/20 bg-theme-surface/30">
      <span id="message-input-instructions" className="sr-only">
        Type your message and press Enter to send. Shift+Enter or Ctrl+Enter for a new line.
        {members && members.length > 0 && ' Type @ to mention a team member.'}
      </span>

      {/* Integrated input container */}
      <div className="relative rounded-2xl border border-theme/40 bg-theme-surface/90 backdrop-blur-sm transition-all duration-200 focus-within:ring-2 focus-within:ring-theme-primary focus-within:border-theme-primary focus-within:bg-theme-surface">

        {/* Mention autocomplete dropdown */}
        {mention.showDropdown && (
          <MentionDropdown
            members={mention.filteredMembers}
            selectedIndex={mention.selectedIndex}
            position={mention.dropdownPosition}
            onSelect={mention.acceptMention}
          />
        )}

        {/*
          Highlight backdrop (z-0): text is color-transparent so only the
          highlight <span> backgrounds are visible. Sits behind the textarea.
        */}
        {hasMentionHighlights && (
          <div
            ref={backdropRef}
            className="absolute inset-0 w-full min-h-[44px] max-h-[120px] px-4 py-2.5 pr-14 rounded-2xl whitespace-pre-wrap break-words overflow-y-auto pointer-events-none border border-transparent text-transparent"
            style={mirrorStyle}
            aria-hidden="true"
          >
            {renderHighlightBackdrop()}
          </div>
        )}

        {/* Textarea (z-10): always fully visible text + cursor */}
        <textarea
          ref={inputRef}
          value={value}
          onChange={handleInputChange}
          onKeyDown={handleKeyDown}
          onScroll={handleScroll}
          placeholder={members && members.length > 0
            ? "Message... (@ to mention)"
            : "Message..."
          }
          rows={1}
          className="relative z-10 w-full min-h-[44px] max-h-[120px] px-4 py-2.5 pr-14 rounded-2xl border-none resize-none bg-transparent text-theme-primary placeholder-theme-muted focus:outline-none disabled:text-theme-muted"
          style={mirrorStyle}
          disabled={sending}
          data-testid="message-input"
          aria-label="Message input"
          aria-describedby="message-input-instructions"
        />

        {/* Send button — anchored bottom-right */}
        <button
          type="button"
          onClick={onSend}
          disabled={!canSend}
          className={`absolute z-20 right-2 bottom-1.5 h-8 w-8 flex items-center justify-center rounded-full transition-all duration-200 ${
            canSend
              ? 'bg-theme-interactive-primary text-white hover:bg-theme-interactive-primary/90 shadow-sm'
              : 'bg-theme-muted/20 text-theme-muted cursor-not-allowed'
          }`}
          data-testid="send-button"
          aria-label={sending ? "Sending message" : "Send message"}
        >
          {sending ? (
            <Loader2 className="h-4 w-4 animate-spin" aria-hidden="true" />
          ) : (
            <ArrowUp className="h-4 w-4" aria-hidden="true" />
          )}
        </button>
      </div>
    </div>
  );
});
