import React, { useState, useEffect, useCallback } from 'react';
import { Routes, Route, Navigate } from 'react-router-dom';
import { TabNavigation, MobileTabNavigation } from '../../components/ui/TabNavigation';
import { Breadcrumb } from '../../components/ui/Breadcrumb';
import { TeamMembersManagement } from '../../components/account/TeamMembersManagement';
import { DelegationsManagement } from '../../components/delegations/DelegationsManagement';
import { InviteTeamMemberModal } from '../../components/account/InviteTeamMemberModal';
import TwoFactorSettings from '../../components/account/TwoFactorSettings';
import { invitationsApi, Invitation } from '../../services/invitationsApi';
import { useSelector } from 'react-redux';
import { RootState } from '../../store';

const tabs = [
  { id: 'profile', label: 'Profile', path: '/dashboard/account/profile', icon: '👤' },
  { id: 'team', label: 'Team', path: '/dashboard/account/team', icon: '👥' },
  { id: 'security', label: 'Security', path: '/dashboard/account/security', icon: '🔒' },
  { id: 'preferences', label: 'Preferences', path: '/dashboard/account/preferences', icon: '⚙️' },
  { id: 'delegations', label: 'Access Control', path: '/dashboard/account/delegations', icon: '🔐' },
];

// Profile Page - Basic user info and account details
const ProfilePage: React.FC = () => {
  return (
    <div className="space-y-6">
      <div className="bg-theme-surface rounded-lg p-6">
        <h2 className="text-xl font-semibold text-theme-primary mb-6">Profile Information</h2>
        
        <div className="flex items-start space-x-6 mb-6">
          <div className="flex-shrink-0">
            <div className="h-24 w-24 rounded-full bg-gradient-to-br from-theme-interactive-primary to-theme-interactive-secondary flex items-center justify-center">
              <span className="text-white text-3xl font-bold">JD</span>
            </div>
            <button className="mt-3 w-full btn-theme btn-theme-secondary text-sm">
              Change Avatar
            </button>
          </div>
          
          <div className="flex-1 grid grid-cols-1 md:grid-cols-2 gap-4">
            <div>
              <label className="block text-sm font-medium text-theme-primary mb-1">First Name</label>
              <input 
                type="text" 
                defaultValue="John" 
                className="w-full px-3 py-2 border border-theme rounded-lg bg-theme-background text-theme-primary"
              />
            </div>
            <div>
              <label className="block text-sm font-medium text-theme-primary mb-1">Last Name</label>
              <input 
                type="text" 
                defaultValue="Doe" 
                className="w-full px-3 py-2 border border-theme rounded-lg bg-theme-background text-theme-primary"
              />
            </div>
            <div>
              <label className="block text-sm font-medium text-theme-primary mb-1">Email</label>
              <input 
                type="email" 
                defaultValue="john.doe@example.com" 
                className="w-full px-3 py-2 border border-theme rounded-lg bg-theme-background text-theme-primary"
              />
            </div>
            <div>
              <label className="block text-sm font-medium text-theme-primary mb-1">Phone</label>
              <input 
                type="tel" 
                defaultValue="+1 (555) 123-4567" 
                className="w-full px-3 py-2 border border-theme rounded-lg bg-theme-background text-theme-primary"
              />
            </div>
            <div>
              <label className="block text-sm font-medium text-theme-primary mb-1">Job Title</label>
              <input 
                type="text" 
                defaultValue="Software Engineer" 
                className="w-full px-3 py-2 border border-theme rounded-lg bg-theme-background text-theme-primary"
              />
            </div>
            <div>
              <label className="block text-sm font-medium text-theme-primary mb-1">Department</label>
              <input 
                type="text" 
                defaultValue="Engineering" 
                className="w-full px-3 py-2 border border-theme rounded-lg bg-theme-background text-theme-primary"
              />
            </div>
          </div>
        </div>
        
        <div className="border-t border-theme pt-4">
          <h3 className="text-lg font-medium text-theme-primary mb-4">Account Information</h3>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div>
              <label className="block text-sm text-theme-secondary mb-1">Account Name</label>
              <p className="text-theme-primary">Acme Corporation</p>
            </div>
            <div>
              <label className="block text-sm text-theme-secondary mb-1">Account ID</label>
              <p className="text-theme-primary font-mono text-sm">acc_1234567890</p>
            </div>
            <div>
              <label className="block text-sm text-theme-secondary mb-1">Your Role</label>
              <span className="inline-flex items-center px-2 py-1 rounded-full text-xs font-medium bg-theme-interactive-primary bg-opacity-10 text-theme-interactive-primary">
                Owner
              </span>
            </div>
            <div>
              <label className="block text-sm text-theme-secondary mb-1">Member Since</label>
              <p className="text-theme-primary">January 15, 2024</p>
            </div>
          </div>
        </div>
        
        <div className="flex justify-end space-x-3 mt-6">
          <button className="btn-theme btn-theme-secondary">Cancel</button>
          <button className="btn-theme btn-theme-primary">Save Changes</button>
        </div>
      </div>
    </div>
  );
};

// Team Page - Combines Users and Invitations
const TeamPage: React.FC = () => {
  const { user: currentUser } = useSelector((state: RootState) => state.auth);
  const [activeView, setActiveView] = useState<'members' | 'invitations'>('members');
  const [invitations, setInvitations] = useState<Invitation[]>([]);
  const [showInviteModal, setShowInviteModal] = useState(false);
  const [loading, setLoading] = useState(false);
  
  const loadInvitationsCallback = useCallback(async () => {
    if (!currentUser?.account?.id) return;
    
    setLoading(true);
    try {
      const response = await invitationsApi.getAccountInvitations(currentUser.account.id);
      if (response.success) {
        setInvitations(response.data);
      }
    } catch (error) {
      console.error('Failed to load invitations:', error);
    } finally {
      setLoading(false);
    }
  }, [currentUser?.account?.id]);

  useEffect(() => {
    loadInvitationsCallback();
  }, [loadInvitationsCallback]);

  const loadInvitations = async () => {
    if (!currentUser?.account?.id) return;
    
    setLoading(true);
    try {
      const response = await invitationsApi.getAccountInvitations(currentUser.account.id);
      if (response.success) {
        setInvitations(response.data);
      }
    } catch (error) {
      console.error('Failed to load invitations:', error);
    } finally {
      setLoading(false);
    }
  };

  const handleInviteSent = () => {
    loadInvitations();
  };

  const handleResendInvitation = async (invitationId: string) => {
    try {
      const response = await invitationsApi.resendInvitation(invitationId);
      if (response.success) {
        loadInvitations();
      }
    } catch (error) {
      console.error('Failed to resend invitation:', error);
    }
  };

  const handleCancelInvitation = async (invitationId: string) => {
    if (!window.confirm('Are you sure you want to cancel this invitation?')) return;
    
    try {
      const response = await invitationsApi.cancelInvitation(invitationId);
      if (response.success) {
        loadInvitations();
      }
    } catch (error) {
      console.error('Failed to cancel invitation:', error);
    }
  };

  const pendingInvitations = invitations.filter(inv => inv.status === 'pending');

  return (
    <div className="space-y-6">
      <div className="bg-theme-surface rounded-lg p-6">
        <div className="flex justify-between items-center mb-6">
          <div>
            <h2 className="text-xl font-semibold text-theme-primary">Team Management</h2>
            <p className="text-theme-secondary mt-1">Manage team members and invitations</p>
          </div>
          <div className="flex space-x-3">
            <button 
              className="btn-theme btn-theme-primary"
              onClick={() => setShowInviteModal(true)}
            >
              Invite Member
            </button>
          </div>
        </div>

        {/* Sub-navigation */}
        <div className="flex space-x-1 mb-6 border-b border-theme">
          <button
            onClick={() => setActiveView('members')}
            className={`px-4 py-2 font-medium text-sm transition-colors ${
              activeView === 'members'
                ? 'text-theme-primary border-b-2 border-theme-interactive-primary'
                : 'text-theme-secondary hover:text-theme-primary'
            }`}
          >
            Team Members
          </button>
          <button
            onClick={() => setActiveView('invitations')}
            className={`px-4 py-2 font-medium text-sm transition-colors ${
              activeView === 'invitations'
                ? 'text-theme-primary border-b-2 border-theme-interactive-primary'
                : 'text-theme-secondary hover:text-theme-primary'
            }`}
          >
            Pending Invitations
            {pendingInvitations.length > 0 && (
              <span className="ml-2 bg-theme-warning bg-opacity-10 text-theme-warning px-2 py-0.5 rounded-full text-xs">
                {pendingInvitations.length}
              </span>
            )}
          </button>
        </div>

        {activeView === 'members' ? (
          <TeamMembersManagement />
        ) : (
          <InvitationsSection 
            invitations={pendingInvitations}
            loading={loading}
            onResend={handleResendInvitation}
            onCancel={handleCancelInvitation}
          />
        )}
      </div>

      <InviteTeamMemberModal
        isOpen={showInviteModal}
        onClose={() => setShowInviteModal(false)}
        onInviteSent={handleInviteSent}
        accountId={currentUser?.account?.id}
      />
    </div>
  );
};

// Security Page - Password, 2FA, Sessions
const SecurityPage: React.FC = () => {
  return (
    <div className="space-y-6">
      <div className="bg-theme-surface rounded-lg p-6">
        <h2 className="text-xl font-semibold text-theme-primary mb-6">Security Settings</h2>
        
        <div className="space-y-6">
          {/* Password Section */}
          <div>
            <h3 className="text-lg font-medium text-theme-primary mb-4">Password</h3>
            <div className="bg-theme-background rounded-lg p-4">
              <p className="text-sm text-theme-secondary mb-4">
                Last changed 30 days ago. We recommend changing your password regularly.
              </p>
              <button className="btn-theme btn-theme-primary">
                Change Password
              </button>
            </div>
          </div>

          {/* Two-Factor Authentication */}
          <TwoFactorSettings />

          {/* Active Sessions */}
          <div>
            <h3 className="text-lg font-medium text-theme-primary mb-4">Active Sessions</h3>
            <div className="space-y-3">
              <div className="bg-theme-background rounded-lg p-4">
                <div className="flex items-center justify-between">
                  <div>
                    <p className="font-medium text-theme-primary">Current Session</p>
                    <p className="text-sm text-theme-secondary">Chrome on MacOS • San Francisco, CA</p>
                    <p className="text-xs text-theme-tertiary mt-1">Active now</p>
                  </div>
                  <span className="bg-theme-success bg-opacity-10 text-theme-success px-2 py-1 rounded text-xs">
                    This device
                  </span>
                </div>
              </div>
              
              <div className="bg-theme-background rounded-lg p-4">
                <div className="flex items-center justify-between">
                  <div>
                    <p className="font-medium text-theme-primary">Mobile App</p>
                    <p className="text-sm text-theme-secondary">iPhone • New York, NY</p>
                    <p className="text-xs text-theme-tertiary mt-1">Last active 2 hours ago</p>
                  </div>
                  <button className="text-theme-error hover:text-theme-error-hover text-sm">
                    Revoke
                  </button>
                </div>
              </div>
            </div>
          </div>

          {/* Security Log */}
          <div>
            <h3 className="text-lg font-medium text-theme-primary mb-4">Recent Security Activity</h3>
            <div className="bg-theme-background rounded-lg p-4">
              <div className="space-y-3">
                <div className="flex items-start space-x-3">
                  <span className="text-theme-success">✓</span>
                  <div>
                    <p className="text-theme-primary">Successful login</p>
                    <p className="text-xs text-theme-tertiary">Today at 9:30 AM from San Francisco, CA</p>
                  </div>
                </div>
                <div className="flex items-start space-x-3">
                  <span className="text-theme-warning">⚠</span>
                  <div>
                    <p className="text-theme-primary">Password changed</p>
                    <p className="text-xs text-theme-tertiary">30 days ago</p>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};

// Preferences Page - Theme, Language, Notifications, Display
const PreferencesPage: React.FC = () => {
  const [preferences, setPreferences] = useState({
    theme: 'system',
    language: 'en',
    emailNotifications: true,
    pushNotifications: false,
    weeklyDigest: true,
    dateFormat: 'MM/DD/YYYY',
    timeZone: 'America/Los_Angeles'
  });
  const [isLoading, setIsLoading] = useState(false);
  const [hasChanges, setHasChanges] = useState(false);
  const [originalPreferences, setOriginalPreferences] = useState(preferences);

  // Load user preferences on component mount
  useEffect(() => {
    loadUserPreferences();
  }, []);

  const loadUserPreferences = async () => {
    try {
      // In a real app, this would fetch from an API
      // For now, we'll load from localStorage or use defaults
      const savedPrefs = localStorage.getItem('userPreferences');
      if (savedPrefs) {
        const parsedPrefs = JSON.parse(savedPrefs);
        setPreferences(parsedPrefs);
        setOriginalPreferences(parsedPrefs);
      }
    } catch (error) {
      console.error('Failed to load preferences:', error);
    }
  };

  const updatePreference = (key: string, value: any) => {
    setPreferences(prev => {
      const updated = { ...prev, [key]: value };
      setHasChanges(JSON.stringify(updated) !== JSON.stringify(originalPreferences));
      return updated;
    });
  };

  const handleSavePreferences = async () => {
    setIsLoading(true);
    try {
      // Simulate API call
      await new Promise(resolve => setTimeout(resolve, 1000));
      
      // Save to localStorage for demo purposes
      localStorage.setItem('userPreferences', JSON.stringify(preferences));
      
      // Update original preferences to reset change tracking
      setOriginalPreferences(preferences);
      setHasChanges(false);
      
      // Show success notification
      // In a real app, you'd use a proper notification system
      alert('Preferences saved successfully!');
    } catch (error) {
      console.error('Failed to save preferences:', error);
      alert('Failed to save preferences. Please try again.');
    } finally {
      setIsLoading(false);
    }
  };

  const handleResetToDefaults = () => {
    if (window.confirm('Are you sure you want to reset all preferences to their default values?')) {
      const defaultPrefs = {
        theme: 'system',
        language: 'en',
        emailNotifications: true,
        pushNotifications: false,
        weeklyDigest: true,
        dateFormat: 'MM/DD/YYYY',
        timeZone: 'America/Los_Angeles'
      };
      setPreferences(defaultPrefs);
      setHasChanges(JSON.stringify(defaultPrefs) !== JSON.stringify(originalPreferences));
    }
  };

  return (
    <div className="space-y-6">
      <div className="bg-theme-surface rounded-lg p-6">
        <h2 className="text-xl font-semibold text-theme-primary mb-6">Preferences</h2>
        
        <div className="space-y-6">
          {/* Appearance */}
          <div>
            <h3 className="text-lg font-medium text-theme-primary mb-4">Appearance</h3>
            <div className="space-y-4">
              <div>
                <label className="block text-sm font-medium text-theme-primary mb-2">Theme</label>
                <select 
                  value={preferences.theme}
                  onChange={(e) => updatePreference('theme', e.target.value)}
                  className="w-full md:w-64 px-3 py-2 border border-theme rounded-lg bg-theme-background text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary focus:border-transparent"
                >
                  <option value="system">System Default</option>
                  <option value="light">Light</option>
                  <option value="dark">Dark</option>
                </select>
              </div>
              
              <div>
                <label className="block text-sm font-medium text-theme-primary mb-2">Language</label>
                <select 
                  value={preferences.language}
                  onChange={(e) => updatePreference('language', e.target.value)}
                  className="w-full md:w-64 px-3 py-2 border border-theme rounded-lg bg-theme-background text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary focus:border-transparent"
                >
                  <option value="en">English</option>
                  <option value="es">Spanish</option>
                  <option value="fr">French</option>
                </select>
              </div>
            </div>
          </div>

          {/* Notifications */}
          <div>
            <h3 className="text-lg font-medium text-theme-primary mb-4">Notifications</h3>
            <div className="space-y-4">
              <div className="flex items-center justify-between p-4 bg-theme-background rounded-lg">
                <div>
                  <h4 className="font-medium text-theme-primary">Email Notifications</h4>
                  <p className="text-sm text-theme-secondary">Receive email updates about your account</p>
                </div>
                <label className="relative inline-flex items-center cursor-pointer">
                  <input 
                    type="checkbox" 
                    className="sr-only peer" 
                    checked={preferences.emailNotifications}
                    onChange={(e) => updatePreference('emailNotifications', e.target.checked)}
                  />
                  <div className="w-11 h-6 bg-theme-surface rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-theme-interactive-primary"></div>
                </label>
              </div>
              
              <div className="flex items-center justify-between p-4 bg-theme-background rounded-lg">
                <div>
                  <h4 className="font-medium text-theme-primary">Push Notifications</h4>
                  <p className="text-sm text-theme-secondary">Get push notifications in your browser</p>
                </div>
                <label className="relative inline-flex items-center cursor-pointer">
                  <input 
                    type="checkbox" 
                    className="sr-only peer" 
                    checked={preferences.pushNotifications}
                    onChange={(e) => updatePreference('pushNotifications', e.target.checked)}
                  />
                  <div className="w-11 h-6 bg-theme-surface rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-theme-interactive-primary"></div>
                </label>
              </div>
              
              <div className="flex items-center justify-between p-4 bg-theme-background rounded-lg">
                <div>
                  <h4 className="font-medium text-theme-primary">Weekly Digest</h4>
                  <p className="text-sm text-theme-secondary">Summary of your weekly activity</p>
                </div>
                <label className="relative inline-flex items-center cursor-pointer">
                  <input 
                    type="checkbox" 
                    className="sr-only peer" 
                    checked={preferences.weeklyDigest}
                    onChange={(e) => updatePreference('weeklyDigest', e.target.checked)}
                  />
                  <div className="w-11 h-6 bg-theme-surface rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-theme-interactive-primary"></div>
                </label>
              </div>
            </div>
          </div>

          {/* Display Preferences */}
          <div>
            <h3 className="text-lg font-medium text-theme-primary mb-4">Display</h3>
            <div className="space-y-4">
              <div>
                <label className="block text-sm font-medium text-theme-primary mb-2">Date Format</label>
                <select 
                  value={preferences.dateFormat}
                  onChange={(e) => updatePreference('dateFormat', e.target.value)}
                  className="w-full md:w-64 px-3 py-2 border border-theme rounded-lg bg-theme-background text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary focus:border-transparent"
                >
                  <option value="MM/DD/YYYY">MM/DD/YYYY</option>
                  <option value="DD/MM/YYYY">DD/MM/YYYY</option>
                  <option value="YYYY-MM-DD">YYYY-MM-DD</option>
                </select>
              </div>
              
              <div>
                <label className="block text-sm font-medium text-theme-primary mb-2">Time Zone</label>
                <select 
                  value={preferences.timeZone}
                  onChange={(e) => updatePreference('timeZone', e.target.value)}
                  className="w-full md:w-64 px-3 py-2 border border-theme rounded-lg bg-theme-background text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary focus:border-transparent"
                >
                  <option value="America/Los_Angeles">Pacific Time (PT)</option>
                  <option value="America/New_York">Eastern Time (ET)</option>
                  <option value="America/Chicago">Central Time (CT)</option>
                  <option value="America/Denver">Mountain Time (MT)</option>
                </select>
              </div>
            </div>
          </div>
        </div>
        
        {/* Save indicator */}
        {hasChanges && (
          <div className="bg-yellow-50 border border-yellow-200 rounded-lg p-3 mt-6">
            <div className="flex items-center">
              <div className="text-yellow-600 mr-2">⚠️</div>
              <span className="text-sm text-yellow-800">You have unsaved changes</span>
            </div>
          </div>
        )}
        
        <div className="flex justify-end space-x-3 mt-6 pt-6 border-t border-theme">
          <button 
            className="btn-theme btn-theme-secondary"
            onClick={handleResetToDefaults}
            disabled={isLoading}
          >
            Reset to Defaults
          </button>
          <button 
            className={`btn-theme ${
              hasChanges ? 'btn-theme-primary' : 'btn-theme-secondary opacity-50 cursor-not-allowed'
            }`}
            onClick={handleSavePreferences}
            disabled={!hasChanges || isLoading}
          >
            {isLoading ? (
              <div className="flex items-center">
                <div className="animate-spin h-4 w-4 border-2 border-white border-t-transparent rounded-full mr-2"></div>
                Saving...
              </div>
            ) : (
              'Save Preferences'
            )}
          </button>
        </div>
      </div>
    </div>
  );
};

// Invitations Section (for Team page)
interface InvitationsSectionProps {
  invitations: Invitation[];
  loading: boolean;
  onResend: (id: string) => void;
  onCancel: (id: string) => void;
}

const InvitationsSection: React.FC<InvitationsSectionProps> = ({
  invitations,
  loading,
  onResend,
  onCancel
}) => {
  const formatTimeAgo = (dateString: string) => {
    const date = new Date(dateString);
    const now = new Date();
    const diffTime = Math.abs(now.getTime() - date.getTime());
    const diffDays = Math.ceil(diffTime / (1000 * 60 * 60 * 24));
    
    if (diffDays === 1) return '1 day ago';
    if (diffDays < 7) return `${diffDays} days ago`;
    if (diffDays < 30) return `${Math.ceil(diffDays / 7)} weeks ago`;
    return `${Math.ceil(diffDays / 30)} months ago`;
  };

  const getDaysUntilExpiry = (expiryString: string) => {
    const expiryDate = new Date(expiryString);
    const now = new Date();
    const diffTime = expiryDate.getTime() - now.getTime();
    const diffDays = Math.ceil(diffTime / (1000 * 60 * 60 * 24));
    
    if (diffDays <= 0) return 'Expired';
    if (diffDays === 1) return 'Expires in 1 day';
    return `Expires in ${diffDays} days`;
  };

  if (loading) {
    return (
      <div className="flex items-center justify-center py-8">
        <div className="animate-spin h-6 w-6 border-2 border-theme-interactive-primary border-t-transparent rounded-full mr-3"></div>
        <span className="text-theme-secondary">Loading invitations...</span>
      </div>
    );
  }

  if (invitations.length === 0) {
    return (
      <div className="text-center py-12">
        <div className="text-4xl mb-4">📧</div>
        <h3 className="text-lg font-medium text-theme-primary mb-2">No pending invitations</h3>
        <p className="text-theme-secondary mb-6">
          When you invite team members, they'll appear here until they accept or the invitation expires.
        </p>
      </div>
    );
  }

  return (
    <div className="space-y-4">
      {invitations.map((invitation) => (
        <div key={invitation.id} className="bg-theme-background rounded-lg p-4 border border-theme">
          <div className="flex items-center justify-between mb-3">
            <div>
              <h4 className="font-medium text-theme-primary">{invitation.email}</h4>
              <p className="text-sm text-theme-secondary">
                Invited as {invitation.role} • Sent {formatTimeAgo(invitation.invited_at)}
              </p>
            </div>
            <div className="flex items-center space-x-2">
              <button 
                className="text-theme-link hover:text-theme-link-hover text-sm"
                onClick={() => onResend(invitation.id)}
              >
                Resend
              </button>
              <button 
                className="text-theme-error hover:text-theme-error-hover text-sm"
                onClick={() => onCancel(invitation.id)}
              >
                Cancel
              </button>
            </div>
          </div>
          <div className={`text-xs ${
            getDaysUntilExpiry(invitation.expires_at).includes('Expired')
              ? 'text-theme-error'
              : getDaysUntilExpiry(invitation.expires_at).includes('1 day')
              ? 'text-theme-warning'
              : 'text-theme-tertiary'
          }`}>
            {getDaysUntilExpiry(invitation.expires_at)}
          </div>
        </div>
      ))}
    </div>
  );
};

export const AccountManagementPage: React.FC = () => {
  const breadcrumbItems = [
    { label: 'Dashboard', path: '/dashboard', icon: '🏠' },
    { label: 'Account', icon: '👤' }
  ];

  return (
    <div className="space-y-6">
      <div>
        <Breadcrumb items={breadcrumbItems} className="mb-4" />
        <h1 className="text-2xl font-bold text-theme-primary">Account Management</h1>
        <p className="text-theme-secondary mt-1">
          Manage your profile, team, security settings, and access control.
        </p>
      </div>

      <div>
        <div className="hidden sm:block">
          <TabNavigation tabs={tabs} basePath="/dashboard/account" />
        </div>
        <MobileTabNavigation tabs={tabs} basePath="/dashboard/account" />
      </div>

      <div>
        <Routes>
          <Route path="/" element={<Navigate to="/dashboard/account/profile" replace />} />
          <Route path="/profile" element={<ProfilePage />} />
          <Route path="/team" element={<TeamPage />} />
          <Route path="/security" element={<SecurityPage />} />
          <Route path="/preferences" element={<PreferencesPage />} />
          <Route path="/delegations" element={<DelegationsManagement />} />
          
          {/* Legacy redirects */}
          <Route path="/users" element={<Navigate to="/dashboard/account/team" replace />} />
          <Route path="/invitations" element={<Navigate to="/dashboard/account/team" replace />} />
          <Route path="/settings" element={<Navigate to="/dashboard/account/preferences" replace />} />
        </Routes>
      </div>
    </div>
  );
};

export default AccountManagementPage;