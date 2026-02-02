import React, { useState, useCallback, useRef, useEffect } from 'react';
import MDEditorOriginal, { ICommand } from '@uiw/react-md-editor';
import { useDropzone } from 'react-dropzone';
import {
  PhotoIcon,
  EyeIcon,
  EyeSlashIcon,
  ArrowsPointingOutIcon,
  ArrowsPointingInIcon
} from '@heroicons/react/24/outline';
import { Button } from '@/shared/components/ui/Button';

// Type cast to bypass strict prop checking with incompatible library types
const MDEditor = MDEditorOriginal as React.ComponentType<any>;

export interface MarkdownEditorProps {
  value: string;
  onChange: (value: string) => void;
  onImageUpload?: (file: File) => Promise<string>;
  height?: number;
  placeholder?: string;
  readOnly?: boolean;
  autoSave?: boolean;
  autoSaveInterval?: number;
  onAutoSave?: (content: string) => Promise<void>;
  className?: string;
}

export const MarkdownEditor: React.FC<MarkdownEditorProps> = ({
  value,
  onChange,
  onImageUpload,
  height = 400,
  placeholder = 'Start writing your article...',
  readOnly = false,
  autoSave = false,
  autoSaveInterval = 30000, // 30 seconds
  onAutoSave,
  className = ''
}) => {
  const [isFullscreen, setIsFullscreen] = useState(false);
  const [isPreviewMode, setIsPreviewMode] = useState(false);
  const [lastSaved, setLastSaved] = useState<Date | null>(null);
  const [isSaving, setIsSaving] = useState(false);
  const autoSaveTimeoutRef = useRef<NodeJS.Timeout | undefined>(undefined);
  const lastValueRef = useRef(value);

  // Auto-save functionality
  const triggerAutoSave = useCallback(async (content: string) => {
    if (!autoSave || !onAutoSave || content === lastValueRef.current) return;
    
    try {
      setIsSaving(true);
      await onAutoSave(content);
      setLastSaved(new Date());
      lastValueRef.current = content;
    } catch {
      console.error('Auto-save failed:', error);
    } finally {
      setIsSaving(false);
    }
  }, [autoSave, onAutoSave]);

  // Set up auto-save timer
  useEffect(() => {
    if (!autoSave || !onAutoSave) return;

    if (autoSaveTimeoutRef.current) {
      clearTimeout(autoSaveTimeoutRef.current);
    }

    autoSaveTimeoutRef.current = setTimeout(() => {
      triggerAutoSave(value);
    }, autoSaveInterval);

    return () => {
      if (autoSaveTimeoutRef.current) {
        clearTimeout(autoSaveTimeoutRef.current);
      }
    };
  }, [value, autoSave, autoSaveInterval, triggerAutoSave]);

  // File upload handling
  const onDrop = useCallback(async (acceptedFiles: File[]) => {
    if (!onImageUpload) return;

    for (const file of acceptedFiles) {
      if (file.type.startsWith('image/')) {
        try {
          const imageUrl = await onImageUpload(file);
          const imageMarkdown = `![${file.name}](${imageUrl})\n`;
          onChange(value + imageMarkdown);
        } catch {
          console.error('Image upload failed:', error);
        }
      }
    }
  }, [value, onChange, onImageUpload]);

  const { getRootProps, getInputProps, isDragActive } = useDropzone({
    onDrop,
    accept: {
      'image/*': ['.png', '.jpg', '.jpeg', '.gif', '.webp']
    },
    multiple: true,
    noClick: true
  });

  // Custom toolbar commands
  const imageCommand: ICommand = {
    name: 'image',
    keyCommand: 'image',
    buttonProps: { 'aria-label': 'Insert image', title: 'Insert image' },
    icon: <PhotoIcon className="w-4 h-4" />,
    execute: (state: { text?: string }) => {
      const input = document.createElement('input');
      input.type = 'file';
      input.accept = 'image/*';
      input.multiple = true;
      input.onchange = async (e) => {
        const files = (e.target as HTMLInputElement).files;
        if (files && onImageUpload) {
          for (let i = 0; i < files.length; i++) {
            try {
              const imageUrl = await onImageUpload(files[i]);
              const imageMarkdown = `![${files[i].name}](${imageUrl})\n`;
              onChange((state.text || '') + imageMarkdown);
            } catch {
              console.error('Image upload failed:', error);
            }
          }
        }
      };
      input.click();
    }
  };

  const fullscreenCommand: ICommand = {
    name: 'fullscreen',
    keyCommand: 'fullscreen',
    buttonProps: { 'aria-label': 'Toggle fullscreen', title: 'Toggle fullscreen' },
    icon: isFullscreen ? (
      <ArrowsPointingInIcon className="w-4 h-4" />
    ) : (
      <ArrowsPointingOutIcon className="w-4 h-4" />
    ),
    execute: () => {
      setIsFullscreen(!isFullscreen);
    }
  };

  const previewToggleCommand: ICommand = {
    name: 'preview-toggle',
    keyCommand: 'preview-toggle',
    buttonProps: { 'aria-label': 'Toggle preview mode', title: 'Toggle preview mode' },
    icon: isPreviewMode ? (
      <EyeSlashIcon className="w-4 h-4" />
    ) : (
      <EyeIcon className="w-4 h-4" />
    ),
    execute: () => {
      setIsPreviewMode(!isPreviewMode);
    }
  };

  // Enhanced toolbar with custom commands
  const commands = [
    'bold', 'italic', 'strikethrough', '|',
    'title1', 'title2', 'title3', '|',
    'hr', 'quote', 'code', 'codeBlock', '|',
    'unorderedListCommand', 'orderedListCommand', '|',
    'link', imageCommand, '|',
    previewToggleCommand, fullscreenCommand
  ];

  return (
    <div
      className={`markdown-editor-container ${className} ${isFullscreen ? 'fixed inset-0 z-50 bg-theme-background' : ''}`}
      {...getRootProps()}
    >
      <input {...getInputProps()} />

      {/* Auto-save status */}
      {autoSave && (
        <div className="flex items-center justify-between mb-2 text-xs text-theme-secondary">
          <div className="flex items-center gap-2">
            {isSaving ? (
              <>
                <div className="w-2 h-2 rounded-full bg-theme-warning animate-pulse" />
                <span>Saving...</span>
              </>
            ) : lastSaved ? (
              <>
                <div className="w-2 h-2 rounded-full bg-theme-success" />
                <span>Last saved: {lastSaved.toLocaleTimeString()}</span>
              </>
            ) : null}
          </div>
          {isFullscreen && (
            <Button
              onClick={() => setIsFullscreen(false)}
              variant="ghost"
              size="sm"
            >
              Exit Fullscreen
            </Button>
          )}
        </div>
      )}

      {/* Drag overlay */}
      {isDragActive && (
        <div className="absolute inset-0 border-2 border-dashed border-theme-primary bg-theme-primary/10 rounded-lg z-10 flex items-center justify-center">
          <div className="text-center">
            <PhotoIcon className="w-12 h-12 text-theme-primary mx-auto mb-2" />
            <p className="text-theme-primary font-medium">Drop images to upload</p>
          </div>
        </div>
      )}

      {/* Editor */}
      <div className="markdown-editor-wrapper">
        <MDEditor
          value={value}
          onChange={(val?: string) => onChange(val || '')}
          commands={commands as ICommand[]}
          preview={isPreviewMode ? 'preview' : 'edit'}
          hideToolbar={readOnly}
          visibleDragBar={false}
          height={isFullscreen ? '100vh' : height}
          data-color-mode="light"
          placeholder={placeholder}
          textareaProps={{
            placeholder,
            style: { fontSize: 14 },
            disabled: readOnly
          }}
        />
      </div>

      {/* Theme styles applied through CSS classes */}
      <style dangerouslySetInnerHTML={{
        __html: `
          .markdown-editor-wrapper .w-md-editor {
            background-color: var(--color-theme-surface);
            border: 1px solid var(--color-theme-border);
            border-radius: 0.5rem;
          }
          
          .markdown-editor-wrapper .w-md-editor-text-textarea,
          .markdown-editor-wrapper .w-md-editor-text {
            background-color: var(--color-theme-surface) !important;
            color: var(--color-theme-primary) !important;
            font-family: 'JetBrains Mono', 'Monaco', 'Consolas', monospace;
          }
          
          .markdown-editor-wrapper .w-md-editor-bar {
            background-color: var(--color-theme-surface);
            border-bottom: 1px solid var(--color-theme-border);
          }
          
          .markdown-editor-wrapper .w-md-editor-bar button {
            color: var(--color-theme-secondary);
            border-radius: 0.25rem;
          }
          
          .markdown-editor-wrapper .w-md-editor-bar button:hover {
            background-color: var(--color-theme-hover);
            color: var(--color-theme-primary);
          }
          
          .markdown-editor-wrapper .w-md-editor-preview {
            background-color: var(--color-theme-surface);
            color: var(--color-theme-primary);
            padding: 1rem;
          }
          
          .markdown-editor-wrapper .w-md-editor-preview h1,
          .markdown-editor-wrapper .w-md-editor-preview h2,
          .markdown-editor-wrapper .w-md-editor-preview h3,
          .markdown-editor-wrapper .w-md-editor-preview h4,
          .markdown-editor-wrapper .w-md-editor-preview h5,
          .markdown-editor-wrapper .w-md-editor-preview h6 {
            color: var(--color-theme-primary);
            border-bottom: 1px solid var(--color-theme-border);
            padding-bottom: 0.5rem;
          }
          
          .markdown-editor-wrapper .w-md-editor-preview blockquote {
            border-left: 4px solid var(--color-theme-primary);
            background-color: var(--color-theme-background);
            margin: 1rem 0;
            padding: 1rem;
          }
          
          .markdown-editor-wrapper .w-md-editor-preview code {
            background-color: var(--color-theme-background);
            color: var(--color-theme-info);
            padding: 0.125rem 0.25rem;
            border-radius: 0.25rem;
            font-family: 'JetBrains Mono', 'Monaco', 'Consolas', monospace;
          }
          
          .markdown-editor-wrapper .w-md-editor-preview pre {
            background-color: var(--color-theme-background) !important;
            border: 1px solid var(--color-theme-border);
            border-radius: 0.5rem;
            padding: 1rem;
            overflow-x: auto;
          }
          
          .markdown-editor-wrapper .w-md-editor-preview pre code {
            background-color: transparent !important;
            color: var(--color-theme-primary);
            padding: 0;
          }
        `
      }} />
    </div>
  );
};