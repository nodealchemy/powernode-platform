import React from 'react';
import {
  FileText,
  Code,
  TestTube,
  Database,
  Settings,
  Layers,
  Wand2,
} from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { Card } from '@/shared/components/ui/Card';
import { cn } from '@/shared/utils/cn';

export const TASK_TEMPLATES = [
  {
    icon: FileText,
    label: 'Documentation',
    task: { key: 'docs', description: 'Write documentation for the feature', acceptance_criteria: 'README updated, inline comments added' }
  },
  {
    icon: Code,
    label: 'Implementation',
    task: { key: 'implement', description: 'Implement the core functionality', acceptance_criteria: 'Feature works as specified' }
  },
  {
    icon: TestTube,
    label: 'Testing',
    task: { key: 'tests', description: 'Write unit and integration tests', acceptance_criteria: 'Test coverage > 80%, all tests pass' }
  },
  {
    icon: Database,
    label: 'Database',
    task: { key: 'migration', description: 'Create database migrations', acceptance_criteria: 'Migrations run successfully, rollback works' }
  },
  {
    icon: Settings,
    label: 'Configuration',
    task: { key: 'config', description: 'Set up configuration and environment', acceptance_criteria: 'Config validated, environment variables documented' }
  },
  {
    icon: Layers,
    label: 'Refactoring',
    task: { key: 'refactor', description: 'Refactor existing code for improvement', acceptance_criteria: 'No regression, improved code quality' }
  },
];

interface PrdTaskTemplatesProps {
  showTemplates: boolean;
  onToggleTemplates: () => void;
  onAddTask: () => void;
  onAddFromTemplate: (template: typeof TASK_TEMPLATES[0]) => void;
}

export const PrdTaskTemplates: React.FC<PrdTaskTemplatesProps> = ({
  showTemplates,
  onToggleTemplates,
  onAddTask,
  onAddFromTemplate,
}) => {
  return (
    <div className="space-y-2">
      {/* Template Dropdown */}
      {showTemplates && (
        <Card className="p-3">
          <p className="text-sm font-medium text-theme-text-primary mb-3">Quick Add from Template</p>
          <div className="grid grid-cols-2 md:grid-cols-3 gap-2">
            {TASK_TEMPLATES.map((template) => (
              <Button
                key={template.label}
                variant="outline"
                size="sm"
                onClick={() => onAddFromTemplate(template)}
                className="justify-start"
              >
                <template.icon className="w-4 h-4 mr-2" />
                {template.label}
              </Button>
            ))}
          </div>
        </Card>
      )}

      <div className="flex items-center gap-2">
        <Button variant="outline" onClick={onAddTask} className="flex-1">
          <FileText className="w-4 h-4 mr-2" />
          Add Task
        </Button>
        <Button
          variant="ghost"
          onClick={onToggleTemplates}
          className={cn(showTemplates && 'bg-theme-bg-secondary')}
        >
          <Wand2 className="w-4 h-4" />
        </Button>
      </div>
    </div>
  );
};
