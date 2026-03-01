import { useState } from 'react';
import type { AiContextEntry, EntryFormData, EntryType } from '../types/context';
import { contextApi } from '../api/contextApi';

interface EntryEditorProps {
  entry?: AiContextEntry;
  contextId: string;
  onSave: (entry: AiContextEntry) => void;
  onCancel: () => void;
  onDelete?: (entryId: string) => void;
}

const ENTRY_TYPES: { value: EntryType; label: string; description: string }[] = [
  { value: 'fact', label: 'Fact', description: 'A verified piece of information' },
  { value: 'preference', label: 'Preference', description: 'User or system preference' },
  { value: 'interaction', label: 'Interaction', description: 'Record of a past interaction' },
  { value: 'knowledge', label: 'Knowledge', description: 'Domain knowledge or expertise' },
  { value: 'skill', label: 'Skill', description: 'A capability or learned skill' },
  { value: 'relationship', label: 'Relationship', description: 'Connection between entities' },
  { value: 'goal', label: 'Goal', description: 'An objective or target' },
  { value: 'constraint', label: 'Constraint', description: 'A limitation or rule' },
];

export function EntryEditor({
  entry,
  contextId,
  onSave,
  onCancel,
  onDelete,
}: EntryEditorProps) {
  const [formData, setFormData] = useState<EntryFormData>({
    entry_type: entry?.entry_type || 'fact',
    key: entry?.key || '',
    content: entry?.content || {},
    content_text: entry?.content_text || '',
    source: entry?.source || '',
    importance_score: entry?.importance_score ?? 0.5,
    confidence_score: entry?.confidence_score ?? 1.0,
    tags: entry?.tags || [],
    metadata: entry?.metadata || {},
  });
  const [tagInput, setTagInput] = useState('');
  const [contentMode, setContentMode] = useState<'simple' | 'json'>(
    entry?.content && Object.keys(entry.content).length > 0 ? 'json' : 'simple'
  );
  const [jsonError, setJsonError] = useState<string | null>(null);
  const [isSaving, setIsSaving] = useState(false);
  const [errors, setErrors] = useState<Record<string, string>>({});

  const isEditing = !!entry;

  const validateForm = (): boolean => {
    const newErrors: Record<string, string> = {};

    if (!formData.key.trim()) {
      newErrors.key = 'Key is required';
    }

    if (contentMode === 'simple' && !formData.content_text?.trim()) {
      newErrors.content_text = 'Content is required';
    }

    if (contentMode === 'json') {
      try {
        if (typeof formData.content === 'string') {
          JSON.parse(formData.content as string);
        }
      } catch (_error) {
        newErrors.content = 'Invalid JSON';
      }
    }

    setErrors(newErrors);
    return Object.keys(newErrors).length === 0;
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!validateForm()) return;

    setIsSaving(true);

    const dataToSave = {
      ...formData,
      content:
        contentMode === 'simple'
          ? { text: formData.content_text }
          : typeof formData.content === 'string'
            ? JSON.parse(formData.content as string)
            : formData.content,
    };

    let response;
    if (isEditing) {
      response = await contextApi.updateEntry(contextId, entry.id, dataToSave);
    } else {
      response = await contextApi.createEntry(contextId, dataToSave);
    }

    if (response.success && response.data) {
      onSave(response.data.entry);
    }

    setIsSaving(false);
  };

  const handleAddTag = () => {
    if (tagInput.trim() && !formData.tags?.includes(tagInput.trim())) {
      setFormData({
        ...formData,
        tags: [...(formData.tags || []), tagInput.trim()],
      });
      setTagInput('');
    }
  };

  const handleRemoveTag = (tag: string) => {
    setFormData({
      ...formData,
      tags: formData.tags?.filter((t) => t !== tag) || [],
    });
  };

  const handleContentJsonChange = (value: string) => {
    try {
      JSON.parse(value);
      setJsonError(null);
    } catch (_error) {
      setJsonError('Invalid JSON');
    }
    setFormData({ ...formData, content: value as unknown as Record<string, unknown> });
  };

  return (
    <form onSubmit={handleSubmit} className="space-y-6">
      <div>
        <h2 className="text-lg font-semibold text-theme-primary">
          {isEditing ? 'Edit Entry' : 'New Entry'}
        </h2>
        <p className="text-sm text-theme-secondary mt-1">
          {isEditing ? 'Modify the entry details below' : 'Add a new entry to this context'}
        </p>
      </div>

      {/* Entry Type */}
      <div>
        <label className="block text-sm font-medium text-theme-primary mb-2">
          Entry Type
        </label>
        <div className="grid grid-cols-2 md:grid-cols-4 gap-2">
          {ENTRY_TYPES.map((type) => (
            <button
              key={type.value}
              type="button"
              onClick={() => setFormData({ ...formData, entry_type: type.value })}
              className={`p-3 text-left border rounded-lg transition-colors ${
                formData.entry_type === type.value
                  ? 'border-theme-interactive-primary bg-theme-surface-selected'
                  : 'border-theme hover:border-theme-secondary'
              }`}
            >
              <p className="font-medium text-theme-primary text-sm">{type.label}</p>
              <p className="text-xs text-theme-tertiary mt-0.5">{type.description}</p>
            </button>
          ))}
        </div>
      </div>

      {/* Key */}
      <div>
        <label className="block text-sm font-medium text-theme-primary mb-1">
          Key <span className="text-theme-error">*</span>
        </label>
        <input
          type="text"
          value={formData.key}
          onChange={(e) => setFormData({ ...formData, key: e.target.value })}
          placeholder="e.g., user_preference_theme, project_deadline"
          className={`w-full px-4 py-2 bg-theme-surface border rounded-lg text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-primary ${
            errors.key ? 'border-theme-error' : 'border-theme'
          }`}
        />
        {errors.key && <p className="text-xs text-theme-error mt-1">{errors.key}</p>}
      </div>

      {/* Content Mode Toggle */}
      <div>
        <div className="flex items-center justify-between mb-2">
          <label className="text-sm font-medium text-theme-primary">Content</label>
          <div className="flex gap-2">
            <button
              type="button"
              onClick={() => setContentMode('simple')}
              className={`px-3 py-1 text-sm rounded ${
                contentMode === 'simple'
                  ? 'bg-theme-interactive-primary text-white'
                  : 'bg-theme-surface text-theme-secondary'
              }`}
            >
              Simple
            </button>
            <button
              type="button"
              onClick={() => setContentMode('json')}
              className={`px-3 py-1 text-sm rounded ${
                contentMode === 'json'
                  ? 'bg-theme-interactive-primary text-white'
                  : 'bg-theme-surface text-theme-secondary'
              }`}
            >
              JSON
            </button>
          </div>
        </div>

        {contentMode === 'simple' ? (
          <textarea
            value={formData.content_text || ''}
            onChange={(e) => setFormData({ ...formData, content_text: e.target.value })}
            placeholder="Enter the content text..."
            rows={4}
            className={`w-full px-4 py-2 bg-theme-surface border rounded-lg text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-primary ${
              errors.content_text ? 'border-theme-error' : 'border-theme'
            }`}
          />
        ) : (
          <textarea
            value={
              typeof formData.content === 'string'
                ? formData.content
                : JSON.stringify(formData.content, null, 2)
            }
            onChange={(e) => handleContentJsonChange(e.target.value)}
            placeholder='{"key": "value"}'
            rows={6}
            className={`w-full px-4 py-2 bg-theme-surface border rounded-lg text-theme-primary font-mono text-sm focus:outline-none focus:ring-2 focus:ring-theme-primary ${
              jsonError || errors.content ? 'border-theme-error' : 'border-theme'
            }`}
          />
        )}
        {(errors.content_text || errors.content || jsonError) && (
          <p className="text-xs text-theme-error mt-1">
            {errors.content_text || errors.content || jsonError}
          </p>
        )}
      </div>

      {/* Source */}
      <div>
        <label className="block text-sm font-medium text-theme-primary mb-1">
          Source
        </label>
        <input
          type="text"
          value={formData.source || ''}
          onChange={(e) => setFormData({ ...formData, source: e.target.value })}
          placeholder="e.g., user_input, api_response, manual_entry"
          className="w-full px-4 py-2 bg-theme-surface border border-theme rounded-lg text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-primary"
        />
      </div>

      {/* Scores */}
      <div className="grid grid-cols-2 gap-4">
        <div>
          <label className="block text-sm font-medium text-theme-primary mb-1">
            Importance Score: {((formData.importance_score || 0) * 100).toFixed(0)}%
          </label>
          <input
            type="range"
            min="0"
            max="1"
            step="0.1"
            value={formData.importance_score || 0.5}
            onChange={(e) =>
              setFormData({ ...formData, importance_score: parseFloat(e.target.value) })
            }
            className="w-full"
          />
          <div className="flex justify-between text-xs text-theme-tertiary">
            <span>Low</span>
            <span>High</span>
          </div>
        </div>
        <div>
          <label className="block text-sm font-medium text-theme-primary mb-1">
            Confidence Score: {((formData.confidence_score || 0) * 100).toFixed(0)}%
          </label>
          <input
            type="range"
            min="0"
            max="1"
            step="0.1"
            value={formData.confidence_score || 1}
            onChange={(e) =>
              setFormData({ ...formData, confidence_score: parseFloat(e.target.value) })
            }
            className="w-full"
          />
          <div className="flex justify-between text-xs text-theme-tertiary">
            <span>Uncertain</span>
            <span>Certain</span>
          </div>
        </div>
      </div>

      {/* Tags */}
      <div>
        <label className="block text-sm font-medium text-theme-primary mb-1">Tags</label>
        <div className="flex gap-2 mb-2">
          <input
            type="text"
            value={tagInput}
            onChange={(e) => setTagInput(e.target.value)}
            onKeyPress={(e) => e.key === 'Enter' && (e.preventDefault(), handleAddTag())}
            placeholder="Add a tag..."
            className="flex-1 px-4 py-2 bg-theme-surface border border-theme rounded-lg text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-primary"
          />
          <button
            type="button"
            onClick={handleAddTag}
            className="px-4 py-2 bg-theme-surface border border-theme text-theme-primary rounded-lg hover:bg-theme-surface transition-colors"
          >
            Add
          </button>
        </div>
        {formData.tags && formData.tags.length > 0 && (
          <div className="flex flex-wrap gap-2">
            {formData.tags.map((tag) => (
              <span
                key={tag}
                className="inline-flex items-center gap-1 px-2 py-1 bg-theme-surface text-theme-secondary rounded text-sm"
              >
                {tag}
                <button
                  type="button"
                  onClick={() => handleRemoveTag(tag)}
                  className="text-theme-tertiary hover:text-theme-error"
                >
                  ×
                </button>
              </span>
            ))}
          </div>
        )}
      </div>

      {/* Actions */}
      <div className="flex justify-between pt-4 border-t border-theme">
        <div>
          {isEditing && onDelete && (
            <button
              type="button"
              onClick={() => onDelete(entry.id)}
              className="px-4 py-2 text-theme-error hover:bg-theme-error hover:bg-opacity-10 rounded-lg transition-colors"
            >
              Delete
            </button>
          )}
        </div>
        <div className="flex gap-3">
          <button
            type="button"
            onClick={onCancel}
            className="px-4 py-2 text-theme-secondary hover:text-theme-primary transition-colors"
          >
            Cancel
          </button>
          <button
            type="submit"
            disabled={isSaving}
            className="px-4 py-2 bg-theme-interactive-primary text-white rounded-lg hover:bg-theme-interactive-primary-hover disabled:opacity-50 transition-colors"
          >
            {isSaving ? 'Saving...' : isEditing ? 'Update Entry' : 'Create Entry'}
          </button>
        </div>
      </div>
    </form>
  );
}
