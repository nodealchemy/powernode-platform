import React, { useRef, useCallback } from 'react';
import { Send, Loader2 } from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';

interface MessageComposerProps {
  value: string;
  onChange: (value: string) => void;
  onSend: () => void;
  onTyping: () => void;
  sending: boolean;
}

export const MessageComposer: React.FC<MessageComposerProps> = ({
  value,
  onChange,
  onSend,
  onTyping,
  sending
}) => {
  const inputRef = useRef<HTMLTextAreaElement>(null);

  const handleInputChange = useCallback((e: React.ChangeEvent<HTMLTextAreaElement>) => {
    onChange(e.target.value);
    onTyping();
  }, [onChange, onTyping]);

  const handleKeyDown = useCallback((e: React.KeyboardEvent) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      onSend();
    }
  }, [onSend]);

  return (
    <div className="p-4 border-t border-theme/30 bg-theme-surface/40 backdrop-blur-sm">
      {/* Screen reader instructions */}
      <span id="message-input-instructions" className="sr-only">
        Type your message and press Enter to send, or Shift+Enter for a new line
      </span>
      <div className="flex gap-3 items-end">
        <div className="flex-1">
          <textarea
            ref={inputRef}
            value={value}
            onChange={handleInputChange}
            onKeyDown={handleKeyDown}
            placeholder="Type your message... (Press Enter to send, Shift+Enter for new line)"
            className="w-full min-h-[44px] max-h-[120px] px-4 py-2.5 border border-theme/40 rounded-xl resize-none bg-theme-surface/90 backdrop-blur-sm text-theme-primary placeholder-theme-muted focus:outline-none focus:ring-2 focus:ring-theme-primary focus:border-theme-primary focus:bg-theme-surface disabled:bg-theme-surface disabled:text-theme-muted transition-all duration-200"
            disabled={sending}
            data-testid="message-input"
            aria-label="Message input"
            aria-describedby="message-input-instructions"
          />
        </div>

        <Button
          variant="primary"
          size="sm"
          rounded="xl"
          onClick={onSend}
          disabled={!value.trim() || sending}
          className="h-[44px] w-[44px] p-0 flex items-center justify-center shrink-0"
          data-testid="send-button"
          aria-label={sending ? "Sending message" : "Send message"}
        >
          {sending ? (
            <Loader2 className="h-5 w-5 animate-spin" aria-hidden="true" />
          ) : (
            <Send className="h-5 w-5" aria-hidden="true" />
          )}
        </Button>
      </div>
    </div>
  );
};
