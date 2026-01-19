import { useState, useEffect, useMemo } from 'react';
import type { IntegrationTemplate, IntegrationTemplateSummary, IntegrationType } from '../../types';
import { integrationsApi } from '../../services/integrationsApi';

interface TemplateSelectionStepProps {
  onSelect: (template: IntegrationTemplate) => void;
  onCancel: () => void;
}

export function TemplateSelectionStep({ onSelect, onCancel }: TemplateSelectionStepProps) {
  const [templates, setTemplates] = useState<IntegrationTemplateSummary[]>([]);
  const [categories, setCategories] = useState<Record<string, number>>({});
  const [isLoading, setIsLoading] = useState(true);
  const [searchQuery, setSearchQuery] = useState('');
  const [selectedType, setSelectedType] = useState<IntegrationType | ''>('');
  const [selectedCategory, setSelectedCategory] = useState('');
  const [loadingTemplate, setLoadingTemplate] = useState<string | null>(null);

  useEffect(() => {
    loadTemplates();
    loadCategories();
  }, []);

  const loadTemplates = async () => {
    setIsLoading(true);
    const response = await integrationsApi.getTemplates(1, 100);
    if (response.success && response.data) {
      setTemplates(response.data.templates);
    }
    setIsLoading(false);
  };

  const loadCategories = async () => {
    const response = await integrationsApi.getTemplateCategories();
    if (response.success && response.data) {
      setCategories(response.data.categories);
    }
  };

  const filteredTemplates = useMemo(() => {
    return templates.filter((template) => {
      const matchesSearch =
        !searchQuery ||
        template.name.toLowerCase().includes(searchQuery.toLowerCase()) ||
        template.description?.toLowerCase().includes(searchQuery.toLowerCase());
      const matchesType = !selectedType || template.integration_type === selectedType;
      const matchesCategory = !selectedCategory || template.category === selectedCategory;
      return matchesSearch && matchesType && matchesCategory;
    });
  }, [templates, searchQuery, selectedType, selectedCategory]);

  const handleSelectTemplate = async (templateId: string) => {
    setLoadingTemplate(templateId);
    const response = await integrationsApi.getTemplate(templateId);
    if (response.success && response.data) {
      onSelect(response.data.template);
    }
    setLoadingTemplate(null);
  };

  const integrationTypes: { value: IntegrationType | ''; label: string }[] = [
    { value: '', label: 'All Types' },
    { value: 'github_action', label: 'GitHub Action' },
    { value: 'webhook', label: 'Webhook' },
    { value: 'mcp_server', label: 'MCP Server' },
    { value: 'rest_api', label: 'REST API' },
    { value: 'custom', label: 'Custom' },
  ];

  return (
    <div className="space-y-6">
      <div>
        <h2 className="text-lg font-semibold text-theme-primary">Select Integration Template</h2>
        <p className="text-sm text-theme-secondary mt-1">
          Choose a template to configure your integration
        </p>
      </div>

      {/* Filters */}
      <div className="flex flex-col sm:flex-row gap-4">
        <div className="flex-1">
          <input
            type="text"
            placeholder="Search templates..."
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            className="w-full px-4 py-2 bg-theme-surface border border-theme rounded-lg text-theme-primary placeholder-theme-tertiary focus:outline-none focus:ring-2 focus:ring-theme-primary"
          />
        </div>
        <div className="flex gap-2">
          <select
            value={selectedType}
            onChange={(e) => setSelectedType(e.target.value as IntegrationType | '')}
            className="px-4 py-2 bg-theme-surface border border-theme rounded-lg text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-primary"
          >
            {integrationTypes.map((type) => (
              <option key={type.value} value={type.value}>
                {type.label}
              </option>
            ))}
          </select>
          <select
            value={selectedCategory}
            onChange={(e) => setSelectedCategory(e.target.value)}
            className="px-4 py-2 bg-theme-surface border border-theme rounded-lg text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-primary"
          >
            <option value="">All Categories</option>
            {Object.keys(categories).map((cat) => (
              <option key={cat} value={cat}>
                {cat} ({categories[cat]})
              </option>
            ))}
          </select>
        </div>
      </div>

      {/* Templates Grid */}
      {isLoading ? (
        <div className="flex items-center justify-center py-12">
          <div className="animate-spin rounded-full h-8 w-8 border-2 border-theme-primary border-t-transparent" />
        </div>
      ) : filteredTemplates.length === 0 ? (
        <div className="text-center py-12">
          <p className="text-theme-secondary">No templates found</p>
          {(searchQuery || selectedType || selectedCategory) && (
            <button
              onClick={() => {
                setSearchQuery('');
                setSelectedType('');
                setSelectedCategory('');
              }}
              className="mt-2 text-sm text-theme-primary hover:underline"
            >
              Clear filters
            </button>
          )}
        </div>
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4 max-h-96 overflow-y-auto">
          {filteredTemplates.map((template) => (
            <button
              key={template.id}
              onClick={() => handleSelectTemplate(template.id)}
              disabled={loadingTemplate === template.id}
              className="flex items-start gap-3 p-4 bg-theme-surface border border-theme rounded-lg hover:border-theme-primary transition-colors text-left disabled:opacity-50 cursor-pointer"
            >
              {template.icon_url ? (
                <img
                  src={template.icon_url}
                  alt={template.name}
                  className="w-10 h-10 rounded-lg"
                />
              ) : (
                <div className="w-10 h-10 rounded-lg bg-theme-surface flex items-center justify-center text-xl">
                  {integrationsApi.getTypeIcon(template.integration_type)}
                </div>
              )}
              <div className="flex-1 min-w-0">
                <div className="flex items-center gap-2">
                  <h3 className="font-medium text-theme-primary truncate">
                    {template.name}
                  </h3>
                  {template.is_featured && (
                    <span className="px-1.5 py-0.5 text-xs bg-theme-warning bg-opacity-10 text-theme-warning rounded">
                      Featured
                    </span>
                  )}
                </div>
                <p className="text-sm text-theme-secondary mt-1 line-clamp-2">
                  {template.description || 'No description'}
                </p>
                <div className="flex items-center gap-2 mt-2 text-xs text-theme-tertiary">
                  <span>{integrationsApi.getTypeLabel(template.integration_type)}</span>
                  <span>•</span>
                  <span>{template.category}</span>
                </div>
              </div>
              {loadingTemplate === template.id && (
                <div className="animate-spin rounded-full h-5 w-5 border-2 border-theme-primary border-t-transparent" />
              )}
            </button>
          ))}
        </div>
      )}

      {/* Actions */}
      <div className="flex justify-end pt-4 border-t border-theme">
        <button
          onClick={onCancel}
          className="px-4 py-2 text-theme-secondary hover:text-theme-primary transition-colors"
        >
          Cancel
        </button>
      </div>
    </div>
  );
}
