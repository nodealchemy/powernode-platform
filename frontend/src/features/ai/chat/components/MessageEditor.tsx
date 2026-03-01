import React, { useState, useRef, useEffect, useCallback } from 'react';
import { Check, X } from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';

interface MessageEditorProps {
  initialContent: string;
  onSave: (content: string) => void;
  onCancel: () => void;
  saving?: boolean;
}

export const MessageEditor: React.FC<MessageEditorProps> = ({
  initialContent,
  onSave,
  onCancel,
  saving = false,
}) => {
  const [content, setContent] = useState(initialContent);
  const textareaRef = useRef<HTMLTextAreaElement>(null);

  useEffect(() => {
    const textarea = textareaRef.current;
    if (textarea) {
      textarea.focus();
      textarea.selectionStart = textarea.value.length;
      textarea.selectionEnd = textarea.value.length;
      // Auto-resize
      textarea.style.height = 'auto';
      textarea.style.height = `${Math.min(textarea.scrollHeight, 300)}px`;
    }
  }, []);

  const handleChange = useCallback((e: React.ChangeEvent<HTMLTextAreaElement>) => {
    setContent(e.target.value);
    const textarea = e.target;
    textarea.style.height = 'auto';
    textarea.style.height = `${Math.min(textarea.scrollHeight, 300)}px`;
  }, []);

  const handleKeyDown = useCallback((e: React.KeyboardEvent<HTMLTextAreaElement>) => {
    if (e.key === 'Escape') {
      e.preventDefault();
      onCancel();
    }
    if (e.key === 'Enter' && (e.ctrlKey || e.metaKey)) {
      e.preventDefault();
      if (content.trim() && content !== initialContent) {
        onSave(content.trim());
      }
    }
  }, [content, initialContent, onCancel, onSave]);

  const hasChanges = content.trim() !== initialContent;

  return (
    <div className="space-y-2">
      <textarea
        ref={textareaRef}
        value={content}
        onChange={handleChange}
        onKeyDown={handleKeyDown}
        disabled={saving}
        rows={1}
        className="w-full resize-none bg-theme-background border border-theme-interactive-primary rounded-md px-2.5 py-1.5 text-sm text-theme-primary focus:outline-none focus:ring-1 focus:ring-theme-interactive-primary disabled:opacity-50"
      />
      <div className="flex items-center gap-1.5 justify-end">
        <span className="text-[10px] text-theme-text-tertiary mr-auto">
          Ctrl+Enter to save, Esc to cancel
        </span>
        <Button
          variant="ghost"
          size="xs"
          onClick={onCancel}
          disabled={saving}
        >
          <X className="h-3 w-3 mr-1" />
          Cancel
        </Button>
        <Button
          variant="primary"
          size="xs"
          onClick={() => onSave(content.trim())}
          disabled={saving || !hasChanges || !content.trim()}
        >
          <Check className="h-3 w-3 mr-1" />
          {saving ? 'Saving...' : 'Save'}
        </Button>
      </div>
    </div>
  );
};
