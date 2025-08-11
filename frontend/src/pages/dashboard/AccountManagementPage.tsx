import React from 'react';
import { Routes, Route, Navigate } from 'react-router-dom';
import { TabNavigation, MobileTabNavigation } from '../../components/ui/TabNavigation';
import { Breadcrumb } from '../../components/ui/Breadcrumb';
import { TeamMembersManagement } from '../../components/account/TeamMembersManagement';
import { DelegationsManagement } from '../../components/delegations/DelegationsManagement';

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
  const [activeView, setActiveView] = React.useState<'members' | 'invitations'>('members');

  return (
    <div className="space-y-6">
      <div className="bg-theme-surface rounded-lg p-6">
        <div className="flex justify-between items-center mb-6">
          <div>
            <h2 className="text-xl font-semibold text-theme-primary">Team Management</h2>
            <p className="text-theme-secondary mt-1">Manage team members and invitations</p>
          </div>
          <div className="flex space-x-3">
            <button className="btn-theme btn-theme-secondary">
              Import Users
            </button>
            <button className="btn-theme btn-theme-primary">
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
            <span className="ml-2 bg-theme-surface px-2 py-0.5 rounded-full text-xs">5</span>
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
            <span className="ml-2 bg-theme-warning bg-opacity-10 text-theme-warning px-2 py-0.5 rounded-full text-xs">2</span>
          </button>
        </div>

        {activeView === 'members' ? <TeamMembersManagement /> : <InvitationsSection />}
      </div>
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
          <div>
            <h3 className="text-lg font-medium text-theme-primary mb-4">Two-Factor Authentication</h3>
            <div className="bg-theme-background rounded-lg p-4">
              <div className="flex items-center justify-between mb-4">
                <div>
                  <p className="font-medium text-theme-primary">Status</p>
                  <p className="text-sm text-theme-secondary">Add an extra layer of security to your account</p>
                </div>
                <span className="bg-theme-error bg-opacity-10 text-theme-error px-3 py-1 rounded-full text-sm">
                  Not Enabled
                </span>
              </div>
              <button className="btn-theme btn-theme-primary">
                Enable 2FA
              </button>
            </div>
          </div>

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
                <select className="w-full md:w-64 px-3 py-2 border border-theme rounded-lg bg-theme-background text-theme-primary">
                  <option>System Default</option>
                  <option>Light</option>
                  <option>Dark</option>
                </select>
              </div>
              
              <div>
                <label className="block text-sm font-medium text-theme-primary mb-2">Language</label>
                <select className="w-full md:w-64 px-3 py-2 border border-theme rounded-lg bg-theme-background text-theme-primary">
                  <option>English</option>
                  <option>Spanish</option>
                  <option>French</option>
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
                  <input type="checkbox" className="sr-only peer" defaultChecked />
                  <div className="w-11 h-6 bg-theme-surface rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-theme-interactive-primary"></div>
                </label>
              </div>
              
              <div className="flex items-center justify-between p-4 bg-theme-background rounded-lg">
                <div>
                  <h4 className="font-medium text-theme-primary">Push Notifications</h4>
                  <p className="text-sm text-theme-secondary">Get push notifications in your browser</p>
                </div>
                <label className="relative inline-flex items-center cursor-pointer">
                  <input type="checkbox" className="sr-only peer" />
                  <div className="w-11 h-6 bg-theme-surface rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-theme-interactive-primary"></div>
                </label>
              </div>
              
              <div className="flex items-center justify-between p-4 bg-theme-background rounded-lg">
                <div>
                  <h4 className="font-medium text-theme-primary">Weekly Digest</h4>
                  <p className="text-sm text-theme-secondary">Summary of your weekly activity</p>
                </div>
                <label className="relative inline-flex items-center cursor-pointer">
                  <input type="checkbox" className="sr-only peer" defaultChecked />
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
                <select className="w-full md:w-64 px-3 py-2 border border-theme rounded-lg bg-theme-background text-theme-primary">
                  <option>MM/DD/YYYY</option>
                  <option>DD/MM/YYYY</option>
                  <option>YYYY-MM-DD</option>
                </select>
              </div>
              
              <div>
                <label className="block text-sm font-medium text-theme-primary mb-2">Time Zone</label>
                <select className="w-full md:w-64 px-3 py-2 border border-theme rounded-lg bg-theme-background text-theme-primary">
                  <option>Pacific Time (PT)</option>
                  <option>Eastern Time (ET)</option>
                  <option>Central Time (CT)</option>
                  <option>Mountain Time (MT)</option>
                </select>
              </div>
            </div>
          </div>
        </div>
        
        <div className="flex justify-end space-x-3 mt-6 pt-6 border-t border-theme">
          <button className="btn-theme btn-theme-secondary">Reset to Defaults</button>
          <button className="btn-theme btn-theme-primary">Save Preferences</button>
        </div>
      </div>
    </div>
  );
};

// Invitations Section (for Team page)
const InvitationsSection: React.FC = () => {
  return (
    <div className="space-y-4">
      <div className="bg-theme-background rounded-lg p-4 border border-theme">
        <div className="flex items-center justify-between mb-3">
          <div>
            <h4 className="font-medium text-theme-primary">sarah.johnson@example.com</h4>
            <p className="text-sm text-theme-secondary">Invited as Developer • Sent 2 days ago</p>
          </div>
          <div className="flex items-center space-x-2">
            <button className="text-theme-link hover:text-theme-link-hover text-sm">
              Resend
            </button>
            <button className="text-theme-error hover:text-theme-error-hover text-sm">
              Cancel
            </button>
          </div>
        </div>
        <div className="text-xs text-theme-tertiary">
          Expires in 5 days
        </div>
      </div>
      
      <div className="bg-theme-background rounded-lg p-4 border border-theme">
        <div className="flex items-center justify-between mb-3">
          <div>
            <h4 className="font-medium text-theme-primary">mike.chen@example.com</h4>
            <p className="text-sm text-theme-secondary">Invited as Admin • Sent 5 days ago</p>
          </div>
          <div className="flex items-center space-x-2">
            <button className="text-theme-link hover:text-theme-link-hover text-sm">
              Resend
            </button>
            <button className="text-theme-error hover:text-theme-error-hover text-sm">
              Cancel
            </button>
          </div>
        </div>
        <div className="text-xs text-theme-tertiary">
          Expires in 2 days
        </div>
      </div>
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