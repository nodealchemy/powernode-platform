import React, { useState, useRef, useCallback, useEffect } from 'react';
import { Send, Paperclip } from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { AttachmentPreview } from './AttachmentPreview';
import type { AttachmentData } from './AttachmentPreview';

interface ChatInputProps {
  onSend: (content: string, files?: File[]) => void;
  disabled?: boolean;
  placeholder?: string;
  maxFileSizeMb?: number;
}

const ACCEPTED_TYPES = [
  'image/png', 'image/jpeg', 'image/gif', 'image/webp', 'image/svg+xml',
  'application/pdf',
  'text/plain', 'text/csv', 'text/markdown',
  'application/json',
];

function fileToPreview(file: File): AttachmentData {
  return {
    name: file.name,
    type: file.type,
    size: file.size,
    preview_url: file.type.startsWith('image/') ? URL.createObjectURL(file) : undefined,
  };
}

export const ChatInput: React.FC<ChatInputProps> = ({
  onSend,
  disabled = false,
  placeholder = 'Type a message... (Ctrl+Enter to send)',
  maxFileSizeMb = 25,
}) => {
  const [value, setValue] = useState('');
  const [pendingFiles, setPendingFiles] = useState<File[]>([]);
  const textareaRef = useRef<HTMLTextAreaElement>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);

  const adjustHeight = useCallback(() => {
    const textarea = textareaRef.current;
    if (textarea) {
      textarea.style.height = 'auto';
      textarea.style.height = `${Math.min(textarea.scrollHeight, 160)}px`;
    }
  }, []);

  useEffect(() => {
    adjustHeight();
  }, [value, adjustHeight]);

  // Cleanup object URLs on unmount
  useEffect(() => {
    return () => {
      pendingFiles.forEach(f => {
        if (f.type.startsWith('image/')) {
          URL.revokeObjectURL(URL.createObjectURL(f));
        }
      });
    };
  }, []);

  const handleSend = useCallback(() => {
    const trimmed = value.trim();
    if ((!trimmed && pendingFiles.length === 0) || disabled) return;
    onSend(trimmed, pendingFiles.length > 0 ? pendingFiles : undefined);
    setValue('');
    setPendingFiles([]);
    if (textareaRef.current) {
      textareaRef.current.style.height = 'auto';
    }
  }, [value, pendingFiles, disabled, onSend]);

  const handleKeyDown = useCallback(
    (e: React.KeyboardEvent<HTMLTextAreaElement>) => {
      if (e.key === 'Enter' && !e.shiftKey && (e.ctrlKey || e.metaKey)) {
        e.preventDefault();
        handleSend();
      }
    },
    [handleSend]
  );

  const addFiles = useCallback((files: FileList | File[]) => {
    const maxBytes = maxFileSizeMb * 1024 * 1024;
    const valid = Array.from(files).filter(f => {
      if (f.size > maxBytes) return false;
      if (ACCEPTED_TYPES.length > 0 && !ACCEPTED_TYPES.includes(f.type)) return false;
      return true;
    });
    if (valid.length > 0) {
      setPendingFiles(prev => [...prev, ...valid]);
    }
  }, [maxFileSizeMb]);

  const handleFileSelect = useCallback(() => {
    fileInputRef.current?.click();
  }, []);

  const handleFileInputChange = useCallback((e: React.ChangeEvent<HTMLInputElement>) => {
    if (e.target.files?.length) {
      addFiles(e.target.files);
      e.target.value = '';
    }
  }, [addFiles]);

  const handlePaste = useCallback((e: React.ClipboardEvent) => {
    const items = e.clipboardData?.items;
    if (!items) return;

    const imageFiles: File[] = [];
    for (let i = 0; i < items.length; i++) {
      const item = items[i];
      if (item.type.startsWith('image/')) {
        const file = item.getAsFile();
        if (file) imageFiles.push(file);
      }
    }
    if (imageFiles.length > 0) {
      addFiles(imageFiles);
    }
  }, [addFiles]);

  const handleRemoveFile = useCallback((index: number) => {
    setPendingFiles(prev => prev.filter((_, i) => i !== index));
  }, []);

  const previews: AttachmentData[] = pendingFiles.map(fileToPreview);

  return (
    <div className="border-t border-theme bg-theme-surface px-4 py-3">
      {/* Pending file previews */}
      {previews.length > 0 && (
        <div className="mb-2">
          <AttachmentPreview attachments={previews} onRemove={handleRemoveFile} />
        </div>
      )}

      <div className="flex items-end gap-2">
        {/* File picker button */}
        <button
          onClick={handleFileSelect}
          disabled={disabled}
          className="p-2 rounded-lg text-theme-text-tertiary hover:text-theme-primary hover:bg-theme-surface-hover transition-colors disabled:opacity-50"
          title="Attach file"
        >
          <Paperclip className="h-4 w-4" />
        </button>

        <textarea
          ref={textareaRef}
          value={value}
          onChange={(e) => setValue(e.target.value)}
          onKeyDown={handleKeyDown}
          onPaste={handlePaste}
          placeholder={placeholder}
          disabled={disabled}
          rows={1}
          className="flex-1 resize-none bg-theme-background border border-theme rounded-lg px-3 py-2 text-sm text-theme-primary placeholder:text-theme-text-tertiary focus:outline-none focus:ring-1 focus:ring-theme-interactive-primary disabled:opacity-50"
        />
        <Button
          variant="primary"
          size="sm"
          onClick={handleSend}
          disabled={disabled || (!value.trim() && pendingFiles.length === 0)}
          title="Send message (Ctrl+Enter)"
        >
          <Send className="h-4 w-4" />
        </Button>
      </div>

      {/* Hidden file input */}
      <input
        ref={fileInputRef}
        type="file"
        multiple
        accept={ACCEPTED_TYPES.join(',')}
        onChange={handleFileInputChange}
        className="hidden"
      />
    </div>
  );
};
