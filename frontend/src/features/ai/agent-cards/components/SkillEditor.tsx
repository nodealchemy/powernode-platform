import React from 'react';
import { Plus, Trash2 } from 'lucide-react';
import { Card, CardHeader, CardContent } from '@/shared/components/ui/Card';
import { Button } from '@/shared/components/ui/Button';
import { Input } from '@/shared/components/ui/Input';

export interface SkillInput {
  id: string;
  name: string;
  description: string;
  tags: string;
  inputSchema: string;
  outputSchema: string;
}

interface SkillEditorProps {
  skills: SkillInput[];
  onAddSkill: () => void;
  onRemoveSkill: (index: number) => void;
  onSkillChange: (index: number, field: keyof SkillInput, value: string) => void;
}

export const SkillEditor: React.FC<SkillEditorProps> = ({
  skills,
  onAddSkill,
  onRemoveSkill,
  onSkillChange,
}) => (
  <Card>
    <CardHeader
      title="Skills / Capabilities"
      action={
        <Button variant="outline" size="sm" onClick={onAddSkill}>
          <Plus className="h-4 w-4 mr-2" />
          Add Skill
        </Button>
      }
    />
    <CardContent className="space-y-4">
      {skills.map((skill, index) => (
        <div
          key={skill.id || index}
          className="p-4 border border-theme rounded-lg space-y-3"
        >
          <div className="flex items-center justify-between">
            <span className="text-sm font-medium text-theme-secondary">
              Skill {index + 1}
            </span>
            {skills.length > 1 && (
              <Button
                variant="ghost"
                size="sm"
                onClick={() => onRemoveSkill(index)}
              >
                <Trash2 className="h-4 w-4 text-theme-danger" />
              </Button>
            )}
          </div>

          <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
            <div>
              <label className="block text-xs text-theme-muted mb-1">ID</label>
              <Input
                value={skill.id}
                onChange={(e) => onSkillChange(index, 'id', e.target.value)}
                placeholder="summarize_text"
              />
            </div>
            <div>
              <label className="block text-xs text-theme-muted mb-1">Name</label>
              <Input
                value={skill.name}
                onChange={(e) => onSkillChange(index, 'name', e.target.value)}
                placeholder="Summarize Text"
              />
            </div>
          </div>

          <div>
            <label className="block text-xs text-theme-muted mb-1">Description</label>
            <Input
              value={skill.description}
              onChange={(e) => onSkillChange(index, 'description', e.target.value)}
              placeholder="Summarizes long text into key points"
            />
          </div>

          <div>
            <label className="block text-xs text-theme-muted mb-1">Tags (comma-separated)</label>
            <Input
              value={skill.tags}
              onChange={(e) => onSkillChange(index, 'tags', e.target.value)}
              placeholder="analysis, text, summarization"
            />
          </div>

          <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
            <div>
              <label className="block text-xs text-theme-muted mb-1">Input Schema (JSON)</label>
              <textarea
                value={skill.inputSchema}
                onChange={(e) => onSkillChange(index, 'inputSchema', e.target.value)}
                placeholder='{"type": "object", "properties": {...}}'
                className="w-full px-3 py-2 border border-theme rounded-lg bg-theme-surface text-theme-primary font-mono text-xs focus:outline-none focus:ring-2 focus:ring-theme-primary"
                rows={8}
              />
            </div>
            <div>
              <label className="block text-xs text-theme-muted mb-1">Output Schema (JSON)</label>
              <textarea
                value={skill.outputSchema}
                onChange={(e) => onSkillChange(index, 'outputSchema', e.target.value)}
                placeholder='{"type": "object", "properties": {...}}'
                className="w-full px-3 py-2 border border-theme rounded-lg bg-theme-surface text-theme-primary font-mono text-xs focus:outline-none focus:ring-2 focus:ring-theme-primary"
                rows={8}
              />
            </div>
          </div>
        </div>
      ))}
    </CardContent>
  </Card>
);
