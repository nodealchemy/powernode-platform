// Role Profile Selector - Grid of profile cards for team role creation
import React, { useEffect, useState } from 'react';
import { Crown, Wrench, Search, Type, TestTube, BookOpen, Settings, ChevronDown, ChevronUp } from 'lucide-react';
import teamsApi from '@/shared/services/ai/TeamsApiService';
import type { RoleProfile } from '@/shared/services/ai/TeamsApiService';

interface RoleProfileSelectorProps {
  onProfileSelect: (profile: RoleProfile) => void;
  onApplyProfile: (profile: RoleProfile) => void;
  onCustomize: (profile: RoleProfile) => void;
}

const PROFILE_ICONS: Record<string, React.ReactNode> = {
  lead: <Crown size={24} />,
  worker: <Wrench size={24} />,
  reviewer: <Search size={24} />,
  type_checker: <Type size={24} />,
  test_writer: <TestTube size={24} />,
  documentation_expert: <BookOpen size={24} />,
  custom: <Settings size={24} />,
};

const PROFILE_COLORS: Record<string, string> = {
  lead: 'border-theme-warning/40 hover:border-theme-warning',
  worker: 'border-theme-info/40 hover:border-theme-info',
  reviewer: 'border-theme-interactive-primary/40 hover:border-theme-interactive-primary',
  type_checker: 'border-theme-success/40 hover:border-theme-success',
  test_writer: 'border-theme-danger/40 hover:border-theme-danger',
  documentation_expert: 'border-theme-secondary/40 hover:border-theme-secondary',
  custom: 'border-theme-accent hover:border-theme-primary',
};

const SELECTED_COLORS: Record<string, string> = {
  lead: 'border-theme-warning bg-theme-warning/10',
  worker: 'border-theme-info bg-theme-info/10',
  reviewer: 'border-theme-interactive-primary bg-theme-interactive-primary/10',
  type_checker: 'border-theme-success bg-theme-success/10',
  test_writer: 'border-theme-danger bg-theme-danger/10',
  documentation_expert: 'border-theme-secondary bg-theme-secondary/10',
  custom: 'border-theme-primary bg-theme-accent',
};

export const RoleProfileSelector: React.FC<RoleProfileSelectorProps> = ({
  onProfileSelect,
  onApplyProfile,
  onCustomize
}) => {
  const [profiles, setProfiles] = useState<RoleProfile[]>([]);
  const [selectedProfile, setSelectedProfile] = useState<RoleProfile | null>(null);
  const [loading, setLoading] = useState(false);
  const [showPreview, setShowPreview] = useState(false);

  useEffect(() => {
    fetchProfiles();
  }, []);

  const fetchProfiles = async () => {
    setLoading(true);
    try {
      const data = await teamsApi.listRoleProfiles({ is_system: true });
      setProfiles(data);
    } catch {
      // Silently fail
    } finally {
      setLoading(false);
    }
  };

  const handleSelect = (profile: RoleProfile) => {
    setSelectedProfile(profile);
    setShowPreview(true);
    onProfileSelect(profile);
  };

  if (loading) {
    return (
      <div className="flex items-center justify-center py-8 text-sm text-theme-secondary">
        Loading role profiles...
      </div>
    );
  }

  return (
    <div className="space-y-4" data-testid="role-profile-selector">
      <h4 className="text-sm font-medium text-theme-primary">Select Role Profile</h4>

      {/* Profile Grid */}
      <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 gap-3">
        {profiles.map(profile => (
          <button
            key={profile.id}
            type="button"
            onClick={() => handleSelect(profile)}
            className={`flex flex-col items-center gap-2 p-4 rounded-lg border-2 transition-all cursor-pointer text-center ${
              selectedProfile?.id === profile.id
                ? SELECTED_COLORS[profile.role_type] || SELECTED_COLORS.custom
                : PROFILE_COLORS[profile.role_type] || PROFILE_COLORS.custom
            }`}
            data-testid={`profile-card-${profile.slug}`}
          >
            <div className="text-theme-primary">
              {PROFILE_ICONS[profile.role_type] || PROFILE_ICONS.custom}
            </div>
            <span className="text-sm font-medium text-theme-primary">{profile.name}</span>
            <span className="text-xs text-theme-secondary line-clamp-2">
              {profile.description?.split('.')[0]}
            </span>
          </button>
        ))}
      </div>

      {/* Profile Preview */}
      {selectedProfile && showPreview && (
        <div className="border border-theme rounded-lg p-4 bg-theme-surface space-y-4" data-testid="profile-preview">
          <div className="flex items-center justify-between">
            <h4 className="text-sm font-medium text-theme-primary">
              Profile: {selectedProfile.name}
            </h4>
            <button
              type="button"
              onClick={() => setShowPreview(!showPreview)}
              className="text-theme-secondary"
            >
              {showPreview ? <ChevronUp size={16} /> : <ChevronDown size={16} />}
            </button>
          </div>

          {/* Communication Style */}
          {selectedProfile.communication_style && Object.keys(selectedProfile.communication_style).length > 0 && (
            <div>
              <h5 className="text-xs font-medium text-theme-secondary mb-2">Communication</h5>
              <div className="flex flex-wrap gap-2">
                {Object.entries(selectedProfile.communication_style).map(([key, value]) => (
                  <span key={key} className="px-2 py-1 text-xs rounded-full bg-theme-accent text-theme-primary">
                    {key}: {String(value)}
                  </span>
                ))}
              </div>
            </div>
          )}

          {/* Quality Checks */}
          {selectedProfile.quality_checks && selectedProfile.quality_checks.length > 0 && (
            <div>
              <h5 className="text-xs font-medium text-theme-secondary mb-2">Quality Checks</h5>
              <ul className="space-y-1">
                {selectedProfile.quality_checks.map((check: Record<string, string>, idx: number) => (
                  <li key={idx} className="flex items-center gap-2 text-xs text-theme-secondary">
                    <span className={`w-2 h-2 rounded-full ${
                      check.severity === 'error' ? 'bg-theme-danger-solid' :
                      check.severity === 'warning' ? 'bg-theme-warning' :
                      'bg-theme-info'
                    }`} />
                    {check.check?.replace(/_/g, ' ')}
                  </li>
                ))}
              </ul>
            </div>
          )}

          {/* System Prompt Preview */}
          {selectedProfile.system_prompt_template && (
            <details>
              <summary className="text-xs font-medium text-theme-secondary cursor-pointer hover:text-theme-primary">
                System Prompt Preview
              </summary>
              <pre className="mt-2 p-3 text-xs bg-theme-accent rounded-md text-theme-secondary overflow-x-auto whitespace-pre-wrap">
                {selectedProfile.system_prompt_template}
              </pre>
            </details>
          )}

          {/* Action Buttons */}
          <div className="flex gap-3 pt-2 border-t border-theme">
            <button
              type="button"
              onClick={() => onApplyProfile(selectedProfile)}
              className="btn-theme btn-theme-primary btn-theme-sm"
            >
              Apply Profile
            </button>
            <button
              type="button"
              onClick={() => onCustomize(selectedProfile)}
              className="btn-theme btn-theme-secondary btn-theme-sm"
            >
              Customize
            </button>
          </div>
        </div>
      )}
    </div>
  );
};
