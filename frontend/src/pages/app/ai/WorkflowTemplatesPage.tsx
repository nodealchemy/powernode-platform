import React, { useState, useEffect, useCallback } from 'react';
import { useNavigate } from 'react-router-dom';
import {
  Plus,
  FileText,
  Zap,
  GitBranch,
  Clock,
  Eye
} from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { Card, CardTitle, CardContent } from '@/shared/components/ui/Card';
import { Button } from '@/shared/components/ui/Button';
import { Badge } from '@/shared/components/ui/Badge';
import { SearchInput } from '@/shared/components/ui/SearchInput';
import { Select } from '@/shared/components/ui/Select';
import { useAuth } from '@/shared/hooks/useAuth';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { workflowsApi } from '@/shared/services/ai';

// Backend template format
interface BackendTemplate {
  id: string;
  name: string;
  description: string;
  category: string;
  execution_mode: 'sequential' | 'parallel' | 'conditional';
  difficulty: 'beginner' | 'intermediate' | 'advanced';
  estimated_duration: string;
  tags: string[];
}

export const WorkflowTemplatesPage: React.FC = () => {
  const { currentUser } = useAuth();
  const { addNotification } = useNotifications();
  const navigate = useNavigate();

  const [templates, setTemplates] = useState<BackendTemplate[]>([]);
  const [loading, setLoading] = useState(true);
  const [searchQuery, setSearchQuery] = useState('');
  const [selectedCategory, setSelectedCategory] = useState('');
  const [selectedDifficulty, setSelectedDifficulty] = useState('');

  // Check permissions
  const canCreateWorkflows = currentUser?.permissions?.includes('ai.workflows.create') || false;

  // Load templates from API
  const loadTemplates = useCallback(async () => {
    try {
      setLoading(true);
      // Cast to BackendTemplate[] since the API returns this format
      const response = await workflowsApi.getTemplates() as unknown as BackendTemplate[];
      setTemplates(response || []);
    } catch (error) {
      if (process.env.NODE_ENV === 'development') {
        console.error('Failed to load templates:', error);
      }
      addNotification({
        type: 'error',
        title: 'Error',
        message: 'Failed to load workflow templates. Please try again.'
      });
      setTemplates([]);
    } finally {
      setLoading(false);
    }
  }, []); // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => {
    loadTemplates();
  }, []); // eslint-disable-line react-hooks/exhaustive-deps

  // Filter templates
  const filteredTemplates = templates.filter(template => {
    const matchesSearch = !searchQuery || 
      template.name.toLowerCase().includes(searchQuery.toLowerCase()) ||
      template.description.toLowerCase().includes(searchQuery.toLowerCase());
    
    const matchesCategory = !selectedCategory || template.category === selectedCategory;
    const matchesDifficulty = !selectedDifficulty || template.difficulty === selectedDifficulty;

    return matchesSearch && matchesCategory && matchesDifficulty;
  });

  // Get unique categories
  const categories = Array.from(new Set(templates.map(t => t.category)));
  const difficulties = ['beginner', 'intermediate', 'advanced'];

  // Handle template creation
  const handleCreateFromTemplate = async (template: BackendTemplate) => {
    if (!canCreateWorkflows) {
      addNotification({
        type: 'error',
        title: 'Permission Denied',
        message: 'You do not have permission to create workflows.'
      });
      return;
    }

    try {
      // Create workflow with template name and description
      const workflow = await workflowsApi.createWorkflow({
        name: `${template.name} Workflow`,
        description: template.description,
        status: 'draft',
        execution_mode: template.execution_mode,
        tags: template.tags
      });

      addNotification({
        type: 'success',
        title: 'Workflow Created',
        message: `Created new workflow from "${template.name}" template.`
      });

      // Navigate to the workflow editor
      navigate(`/app/ai/workflows/${workflow.id}/edit`);
    } catch (error) {
      if (process.env.NODE_ENV === 'development') {
        console.error('Failed to create workflow from template:', error);
      }
      addNotification({
        type: 'error',
        title: 'Creation Failed',
        message: 'Failed to create workflow from template. Please try again.'
      });
    }
  };

  // Get difficulty color
  const getDifficultyColor = (difficulty: string) => {
    switch (difficulty) {
      case 'beginner': return 'bg-theme-success/10 text-theme-success border-theme-success/20';
      case 'intermediate': return 'bg-theme-warning/10 text-theme-warning border-theme-warning/20';
      case 'advanced': return 'bg-theme-danger/10 text-theme-danger border-theme-danger/20';
      default: return 'bg-theme-secondary text-theme-muted border-theme-border';
    }
  };

  // Get execution mode icon
  const getExecutionModeIcon = (executionMode: string) => {
    switch (executionMode) {
      case 'sequential': return FileText;
      case 'parallel': return GitBranch;
      case 'conditional': return Zap;
      default: return FileText;
    }
  };

  return (
    <PageContainer
      title="Workflow Templates"
      description="Pre-built workflow templates for common automation tasks"
      breadcrumbs={[
        { label: 'AI', href: '/app/ai' },
        { label: 'Templates' }
      ]}
    >
      <div className="space-y-6">
        {/* Filters */}
        <div className="flex flex-col sm:flex-row gap-4">
          <div className="flex-1">
            <SearchInput
              placeholder="Search templates..."
              value={searchQuery}
              onChange={setSearchQuery}
            />
          </div>
          <div className="flex gap-2">
            <Select
              value={selectedCategory}
              onChange={(value) => setSelectedCategory(value)}
              options={[
                { value: '', label: 'All Categories' },
                ...categories.map(category => ({
                  value: category,
                  label: category.charAt(0).toUpperCase() + category.slice(1)
                }))
              ]}
              className="w-40"
            />
            <Select
              value={selectedDifficulty}
              onChange={(value) => setSelectedDifficulty(value)}
              options={[
                { value: '', label: 'All Levels' },
                ...difficulties.map(difficulty => ({
                  value: difficulty,
                  label: difficulty.charAt(0).toUpperCase() + difficulty.slice(1)
                }))
              ]}
              className="w-40"
            />
          </div>
        </div>

        {/* Template Grid */}
        {loading ? (
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
            {[...Array(6)].map((_, i) => (
              <Card key={i} className="animate-pulse">
                <CardContent className="p-6">
                  <div className="h-4 bg-theme-secondary rounded w-3/4 mb-2"></div>
                  <div className="h-3 bg-theme-secondary rounded w-full mb-4"></div>
                  <div className="h-3 bg-theme-secondary rounded w-1/2"></div>
                </CardContent>
              </Card>
            ))}
          </div>
        ) : filteredTemplates.length > 0 ? (
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
            {filteredTemplates.map(template => {
              const ExecutionIcon = getExecutionModeIcon(template.execution_mode);

              return (
                <Card key={template.id} className="hover:shadow-md transition-shadow">
                  <div className="p-4">
                    <div className="flex items-start justify-between">
                      <CardTitle className="text-lg">{template.name}</CardTitle>
                    </div>
                  </div>
                  <CardContent className="space-y-4 pt-0">
                    <p className="text-sm text-theme-muted line-clamp-3">
                      {template.description}
                    </p>

                    <div className="flex flex-wrap gap-2">
                      <Badge variant="outline" className="text-xs">
                        {template.category}
                      </Badge>
                      {template.difficulty && (
                        <Badge className={`text-xs ${getDifficultyColor(template.difficulty)}`}>
                          {template.difficulty}
                        </Badge>
                      )}
                      <Badge variant="outline" className="text-xs flex items-center gap-1">
                        <ExecutionIcon className="h-3 w-3" />
                        {template.execution_mode}
                      </Badge>
                    </div>

                    <div className="space-y-2 text-sm">
                      {template.estimated_duration && (
                        <div className="flex items-center gap-2 text-theme-muted">
                          <Clock className="h-4 w-4" />
                          <span>{template.estimated_duration}</span>
                        </div>
                      )}
                    </div>

                    {template.tags && template.tags.length > 0 && (
                      <div className="flex flex-wrap gap-1">
                        {template.tags.slice(0, 3).map(tag => (
                          <Badge key={tag} variant="outline" className="text-xs">
                            {tag}
                          </Badge>
                        ))}
                        {template.tags.length > 3 && (
                          <Badge variant="outline" className="text-xs">
                            +{template.tags.length - 3} more
                          </Badge>
                        )}
                      </div>
                    )}

                    <div className="flex gap-2 pt-2">
                      <Button
                        variant="outline"
                        size="sm"
                        onClick={() => {
                          addNotification({
                            type: 'info',
                            title: 'Template Details',
                            message: `Template: ${template.name}\nCategory: ${template.category}\nDifficulty: ${template.difficulty}`
                          });
                        }}
                        className="flex-1"
                      >
                        <Eye className="h-4 w-4 mr-1" />
                        View
                      </Button>
                      {canCreateWorkflows && (
                        <Button
                          size="sm"
                          onClick={() => handleCreateFromTemplate(template)}
                          className="flex-1"
                        >
                          <Plus className="h-4 w-4 mr-1" />
                          Use
                        </Button>
                      )}
                    </div>
                  </CardContent>
                </Card>
              );
            })}
          </div>
        ) : (
          <Card>
            <CardContent className="text-center py-12">
              <FileText className="h-12 w-12 text-theme-muted mx-auto mb-4 opacity-50" />
              <h3 className="text-lg font-medium mb-2">No templates found</h3>
              <p className="text-theme-muted mb-4">
                {searchQuery || selectedCategory || selectedDifficulty
                  ? 'Try adjusting your filters to see more templates.'
                  : 'No workflow templates are available at the moment.'}
              </p>
              {(searchQuery || selectedCategory || selectedDifficulty) && (
                <Button
                  variant="outline"
                  onClick={() => {
                    setSearchQuery('');
                    setSelectedCategory('');
                    setSelectedDifficulty('');
                  }}
                >
                  Clear Filters
                </Button>
              )}
            </CardContent>
          </Card>
        )}
      </div>
    </PageContainer>
  );
};