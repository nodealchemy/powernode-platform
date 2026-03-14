import { useState } from 'react';
import { skillsApi } from '../services/skillsApi';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { Input } from '@/shared/components/ui/Input';
import { Select } from '@/shared/components/ui/Select';
import { Button } from '@/shared/components/ui/Button';
import type { SkillCategory, SkillFormData } from '../types';

const CATEGORY_OPTIONS: { value: SkillCategory; label: string }[] = [
  { value: 'productivity', label: 'Productivity' },
  { value: 'sales', label: 'Sales' },
  { value: 'customer_support', label: 'Customer Support' },
  { value: 'product_management', label: 'Product Management' },
  { value: 'marketing', label: 'Marketing' },
  { value: 'legal', label: 'Legal' },
  { value: 'finance', label: 'Finance' },
  { value: 'data', label: 'Data' },
  { value: 'business_search', label: 'Business Search' },
  { value: 'bio_research', label: 'Bio Research' },
  { value: 'skill_management', label: 'Skill Management' },
  { value: 'code_intelligence', label: 'Code Intelligence' },
  { value: 'testing_qa', label: 'Testing & QA' },
  { value: 'devops', label: 'DevOps' },
  { value: 'security', label: 'Security' },
  { value: 'sre_observability', label: 'SRE & Observability' },
  { value: 'database_ops', label: 'Database Ops' },
  { value: 'release_management', label: 'Release Management' },
  { value: 'research', label: 'Research' },
  { value: 'documentation', label: 'Documentation' },
];

interface SkillEditorProps {
  onSaved: () => void;
  onCancel: () => void;
}

export function SkillEditor({ onSaved, onCancel }: SkillEditorProps) {
  const { showNotification } = useNotifications();
  const [saving, setSaving] = useState(false);
  const [formData, setFormData] = useState<SkillFormData>({
    name: '',
    description: '',
    category: 'productivity',
    status: 'active',
    system_prompt: '',
    commands: [],
    tags: [],
  });
  const [tagInput, setTagInput] = useState('');
  const [errors, setErrors] = useState<Record<string, string>>({});

  const validate = (): boolean => {
    const errs: Record<string, string> = {};
    if (!formData.name.trim()) errs.name = 'Name is required';
    if (!formData.category) errs.category = 'Category is required';
    setErrors(errs);
    return Object.keys(errs).length === 0;
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!validate()) return;

    setSaving(true);
    const response = await skillsApi.createSkill(formData);
    if (response.success) {
      showNotification('Skill created', 'success');
      onSaved();
    } else {
      showNotification(response.error || 'Failed to create skill', 'error');
    }
    setSaving(false);
  };

  const addTag = () => {
    const tag = tagInput.trim().toLowerCase();
    if (tag && !formData.tags.includes(tag)) {
      setFormData({ ...formData, tags: [...formData.tags, tag] });
    }
    setTagInput('');
  };

  const removeTag = (tag: string) => {
    setFormData({ ...formData, tags: formData.tags.filter((t) => t !== tag) });
  };

  return (
    <div className="max-w-2xl">
      <form onSubmit={handleSubmit} className="space-y-6">
        <div className="bg-theme-surface border border-theme rounded-lg p-6">
          <h3 className="text-lg font-medium text-theme-primary mb-4">Create Skill</h3>

          <div className="space-y-4">
            <Input
              label="Name"
              value={formData.name}
              onChange={(e) => setFormData({ ...formData, name: e.target.value })}
              placeholder="e.g., My Custom Skill"
              error={errors.name}
              required
            />

            <div>
              <label className="block text-sm font-medium text-theme-primary mb-1">
                Description
              </label>
              <textarea
                value={formData.description}
                onChange={(e) => setFormData({ ...formData, description: e.target.value })}
                placeholder="What does this skill do?"
                rows={3}
                className="w-full px-3 py-2 bg-theme-surface border border-theme rounded-md text-theme-primary placeholder-theme-tertiary focus:outline-none focus:ring-2 focus:ring-theme-primary"
              />
            </div>

            <Select
              label="Category"
              value={formData.category}
              onChange={(value) =>
                setFormData({ ...formData, category: value as SkillCategory })
              }
              options={CATEGORY_OPTIONS}
              error={errors.category}
            />

            <Select
              label="Status"
              value={formData.status}
              onChange={(value) =>
                setFormData({ ...formData, status: value as SkillFormData['status'] })
              }
              options={[
                { value: 'active', label: 'Active' },
                { value: 'draft', label: 'Draft' },
                { value: 'inactive', label: 'Inactive' },
              ]}
            />

            <div>
              <label className="block text-sm font-medium text-theme-primary mb-1">
                System Prompt
              </label>
              <textarea
                value={formData.system_prompt}
                onChange={(e) => setFormData({ ...formData, system_prompt: e.target.value })}
                placeholder="Instructions for the AI when this skill is active..."
                rows={6}
                className="w-full px-3 py-2 bg-theme-surface border border-theme rounded-md text-theme-primary placeholder-theme-tertiary focus:outline-none focus:ring-2 focus:ring-theme-primary font-mono text-sm"
              />
            </div>

            {/* Dependencies — shown only for existing skills, not create */}
            {/* For now just show a note, since SkillEditor is create-only */}
            <div className="text-xs text-theme-tertiary">
              Dependencies can be configured after creation via the Skill Graph.
            </div>

            {/* Tags */}
            <div>
              <label className="block text-sm font-medium text-theme-primary mb-1">Tags</label>
              <div className="flex gap-2 mb-2">
                <Input
                  value={tagInput}
                  onChange={(e) => setTagInput(e.target.value)}
                  onKeyDown={(e) => {
                    if (e.key === 'Enter') {
                      e.preventDefault();
                      addTag();
                    }
                  }}
                  placeholder="Add tag..."
                  className="flex-1"
                />
                <Button type="button" variant="secondary" onClick={addTag} size="sm">
                  Add
                </Button>
              </div>
              {formData.tags.length > 0 && (
                <div className="flex flex-wrap gap-1">
                  {formData.tags.map((tag) => (
                    <span
                      key={tag}
                      className="inline-flex items-center gap-1 px-2 py-0.5 text-xs rounded bg-theme-surface-secondary text-theme-secondary"
                    >
                      {tag}
                      <button
                        type="button"
                        onClick={() => removeTag(tag)}
                        className="text-theme-tertiary hover:text-theme-error"
                      >
                        &times;
                      </button>
                    </span>
                  ))}
                </div>
              )}
            </div>
          </div>
        </div>

        <div className="flex justify-end gap-3">
          <Button type="button" variant="secondary" onClick={onCancel}>
            Cancel
          </Button>
          <Button type="submit" variant="primary" disabled={saving}>
            {saving ? 'Creating...' : 'Create Skill'}
          </Button>
        </div>
      </form>
    </div>
  );
}
