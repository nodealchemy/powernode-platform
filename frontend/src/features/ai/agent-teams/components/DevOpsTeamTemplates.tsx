import React, { useState, useEffect } from 'react';
import { Rocket, Server, AlertTriangle, Users, Loader2 } from 'lucide-react';
import { agentTeamsApi } from '../services/agentTeamsApi';
import { useNotifications } from '@/shared/hooks/useNotifications';

interface TeamTemplate {
  id: string;
  name: string;
  description: string;
  category: string;
  roles: string[];
}

const TEMPLATE_ICONS: Record<string, React.ElementType> = {
  'Deployment Team': Rocket,
  'Incident Response': AlertTriangle,
  'Infrastructure Scaling': Server
};

export const DevOpsTeamTemplates: React.FC = () => {
  const [templates, setTemplates] = useState<TeamTemplate[]>([]);
  const [loading, setLoading] = useState(true);
  const [deploying, setDeploying] = useState<string | null>(null);
  const { addNotification } = useNotifications();

  useEffect(() => {
    const fetchTemplates = async () => {
      try {
        const data = await agentTeamsApi.getDevOpsTemplates();
        setTemplates(data);
      } catch {
        // Silently handle
      } finally {
        setLoading(false);
      }
    };
    fetchTemplates();
  }, []);

  const handleDeploy = async (template: TeamTemplate) => {
    setDeploying(template.id);
    try {
      await agentTeamsApi.createFromTemplate(template.id, {});
      addNotification({
        type: 'success',
        title: 'Team Created',
        message: `${template.name} team deployed successfully`
      });
    } catch {
      addNotification({
        type: 'error',
        title: 'Deploy Failed',
        message: `Failed to deploy ${template.name} team`
      });
    } finally {
      setDeploying(null);
    }
  };

  if (loading) {
    return (
      <div className="flex items-center justify-center py-12">
        <Loader2 className="h-6 w-6 animate-spin text-theme-primary" />
      </div>
    );
  }

  if (templates.length === 0) {
    return (
      <div className="text-center py-12 bg-theme-surface border border-theme rounded-lg">
        <Server size={48} className="mx-auto text-theme-secondary mb-4" />
        <h3 className="text-lg font-semibold text-theme-primary mb-2">No DevOps Templates</h3>
        <p className="text-theme-secondary">
          DevOps team templates will appear here once configured
        </p>
      </div>
    );
  }

  return (
    <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
      {templates.map(template => {
        const Icon = TEMPLATE_ICONS[template.name] || Users;
        return (
          <div
            key={template.id}
            className="bg-theme-surface border border-theme rounded-lg p-6 hover:shadow-lg transition-shadow"
          >
            <div className="flex items-center gap-3 mb-4">
              <div className="p-2 bg-theme-primary/10 rounded-lg">
                <Icon className="h-6 w-6 text-theme-primary" />
              </div>
              <div>
                <h3 className="text-sm font-semibold text-theme-primary">{template.name}</h3>
                <p className="text-xs text-theme-secondary">{template.category}</p>
              </div>
            </div>

            <p className="text-sm text-theme-secondary mb-4">{template.description}</p>

            {/* Roles */}
            <div className="mb-4">
              <h4 className="text-xs font-medium text-theme-secondary mb-2">Roles</h4>
              <div className="flex flex-wrap gap-1">
                {template.roles.map((role, idx) => (
                  <span
                    key={idx}
                    className="px-2 py-0.5 text-xs bg-theme-accent text-theme-secondary rounded-full"
                  >
                    {role}
                  </span>
                ))}
              </div>
            </div>

            <button
              type="button"
              onClick={() => handleDeploy(template)}
              disabled={deploying === template.id}
              className="w-full py-2 text-sm font-medium text-white bg-theme-primary rounded-lg hover:bg-theme-primary/90 disabled:opacity-50 transition-colors flex items-center justify-center gap-2"
            >
              {deploying === template.id ? (
                <Loader2 className="h-4 w-4 animate-spin" />
              ) : (
                <Rocket className="h-4 w-4" />
              )}
              Deploy Team
            </button>
          </div>
        );
      })}
    </div>
  );
};
