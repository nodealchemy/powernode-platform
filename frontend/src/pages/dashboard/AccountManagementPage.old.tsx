import React from 'react';
import { Routes, Route, Navigate } from 'react-router-dom';
import { TabNavigation, MobileTabNavigation } from '../../components/ui/TabNavigation';
import { Breadcrumb } from '../../components/ui/Breadcrumb';
import UsersPage from './UsersPage';
import { DelegationsManagement } from '../../components/delegations/DelegationsManagement';
import AccountsPage from './AccountsPage';
import { SettingsPage } from './SettingsPage';

const tabs = [
  { id: 'profile', label: 'My Profile', path: '/dashboard/account/profile', icon: '👤' },
  { id: 'settings', label: 'Settings', path: '/dashboard/account/settings', icon: '⚙️' },
  { id: 'users', label: 'Team Members', path: '/dashboard/account/users', icon: '👥' },
  { id: 'invitations', label: 'Invitations', path: '/dashboard/account/invitations', icon: '✉️' },
  { id: 'delegations', label: 'Access Control', path: '/dashboard/account/delegations', icon: '🔐' },
];

const ProfilePage: React.FC = () => {
  const [activeSection, setActiveSection] = React.useState('profile');

  const sections = [
    { id: 'profile', label: 'Profile Information', icon: '👤' },
    { id: 'preferences', label: 'Preferences', icon: '🎨' },
    { id: 'notifications', label: 'Notifications', icon: '🔔' },
    { id: 'security', label: 'Security', icon: '🔒' },
    { id: 'roles', label: 'Roles & Permissions', icon: '🔐' },
  ];

  return (
    <div className="space-y-6">
      {/* Section Navigation */}
      <div className="bg-theme-surface rounded-lg p-4">
        <div className="flex flex-wrap gap-2">
          {sections.map((section) => (
            <button
              key={section.id}
              onClick={() => setActiveSection(section.id)}
              className={`px-4 py-2 rounded-lg font-medium text-sm transition-colors duration-150 ${
                activeSection === section.id
                  ? 'bg-theme-interactive-primary text-white'
                  : 'bg-theme-background text-theme-secondary hover:bg-theme-surface-hover hover:text-theme-primary'
              }`}
            >
              <span className="mr-2">{section.icon}</span>
              {section.label}
            </button>
          ))}
        </div>
      </div>

      {/* Profile Information Section */}
      {activeSection === 'profile' && (
        <div className="bg-theme-surface rounded-lg p-6">
          <h2 className="text-xl font-semibold text-theme-primary mb-6">Profile Information</h2>
          
          <div className="flex items-start space-x-6 mb-6">
            <div className="flex-shrink-0">
              <div className="h-24 w-24 rounded-full bg-gradient-to-br from-blue-500 to-purple-600 flex items-center justify-center">
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
                  className="w-full px-3 py-2 border border-theme rounded-lg bg-theme-background text-theme-primary focus:ring-2 focus:ring-theme-interactive-primary focus:border-theme-interactive-primary"
                />
              </div>
              <div>
                <label className="block text-sm font-medium text-theme-primary mb-1">Last Name</label>
                <input 
                  type="text" 
                  defaultValue="Doe" 
                  className="w-full px-3 py-2 border border-theme rounded-lg bg-theme-background text-theme-primary focus:ring-2 focus:ring-theme-interactive-primary focus:border-theme-interactive-primary"
                />
              </div>
              <div>
                <label className="block text-sm font-medium text-theme-primary mb-1">Email</label>
                <input 
                  type="email" 
                  defaultValue="john.doe@example.com" 
                  className="w-full px-3 py-2 border border-theme rounded-lg bg-theme-background text-theme-primary focus:ring-2 focus:ring-theme-interactive-primary focus:border-theme-interactive-primary"
                />
              </div>
              <div>
                <label className="block text-sm font-medium text-theme-primary mb-1">Phone</label>
                <input 
                  type="tel" 
                  defaultValue="+1 (555) 123-4567" 
                  className="w-full px-3 py-2 border border-theme rounded-lg bg-theme-background text-theme-primary focus:ring-2 focus:ring-theme-interactive-primary focus:border-theme-interactive-primary"
                />
              </div>
            </div>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-2 gap-4 mb-6">
            <div>
              <label className="block text-sm font-medium text-theme-primary mb-1">Department</label>
              <input 
                type="text" 
                defaultValue="Engineering" 
                className="w-full px-3 py-2 border border-theme rounded-lg bg-theme-background text-theme-primary focus:ring-2 focus:ring-theme-interactive-primary focus:border-theme-interactive-primary"
              />
            </div>
            <div>
              <label className="block text-sm font-medium text-theme-primary mb-1">Title</label>
              <input 
                type="text" 
                defaultValue="Senior Developer" 
                className="w-full px-3 py-2 border border-theme rounded-lg bg-theme-background text-theme-primary focus:ring-2 focus:ring-theme-interactive-primary focus:border-theme-interactive-primary"
              />
            </div>
            <div>
              <label className="block text-sm font-medium text-theme-primary mb-1">Location</label>
              <input 
                type="text" 
                defaultValue="New York, NY" 
                className="w-full px-3 py-2 border border-theme rounded-lg bg-theme-background text-theme-primary focus:ring-2 focus:ring-theme-interactive-primary focus:border-theme-interactive-primary"
              />
            </div>
            <div>
              <label className="block text-sm font-medium text-theme-primary mb-1">Time Zone</label>
              <select className="w-full px-3 py-2 border border-theme rounded-lg bg-theme-background text-theme-primary focus:ring-2 focus:ring-theme-interactive-primary focus:border-theme-interactive-primary">
                <option>Eastern Time (US & Canada)</option>
                <option>Central Time (US & Canada)</option>
                <option>Mountain Time (US & Canada)</option>
                <option>Pacific Time (US & Canada)</option>
              </select>
            </div>
          </div>

          <div className="mb-6">
            <label className="block text-sm font-medium text-theme-primary mb-1">Bio</label>
            <textarea 
              rows={4}
              defaultValue="Passionate about building great software and solving complex problems."
              className="w-full px-3 py-2 border border-theme rounded-lg bg-theme-background text-theme-primary focus:ring-2 focus:ring-theme-interactive-primary focus:border-theme-interactive-primary"
            />
          </div>

          <div className="flex justify-end space-x-3">
            <button className="btn-theme btn-theme-secondary">Cancel</button>
            <button className="btn-theme btn-theme-primary">Save Changes</button>
          </div>
        </div>
      )}

      {/* Preferences Section */}
      {activeSection === 'preferences' && <PreferencesSection />}
      
      {/* Notifications Section */}
      {activeSection === 'notifications' && <NotificationsSection />}
      
      {/* Security Section */}
      {activeSection === 'security' && <SecuritySection />}
      
      {/* Roles & Permissions Section */}
      {activeSection === 'roles' && <RolesPermissionsSection />}
    </div>
  );
};

const PreferencesSection: React.FC = () => {
  return (
    <div className="space-y-6">
      <div className="bg-theme-surface rounded-lg p-6">
        <h2 className="text-xl font-semibold text-theme-primary mb-6">User Preferences</h2>
        <p className="text-theme-secondary mb-6">Customize your application experience</p>
        
        <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
          <div>
            <label className="block text-sm font-medium text-theme-primary mb-2">Theme</label>
            <select className="w-full px-3 py-2 border border-theme rounded-lg bg-theme-background text-theme-primary focus:ring-2 focus:ring-theme-interactive-primary focus:border-theme-interactive-primary">
              <option>Light</option>
              <option>Dark</option>
              <option>System</option>
            </select>
          </div>
          
          <div>
            <label className="block text-sm font-medium text-theme-primary mb-2">Language</label>
            <select className="w-full px-3 py-2 border border-theme rounded-lg bg-theme-background text-theme-primary focus:ring-2 focus:ring-theme-interactive-primary focus:border-theme-interactive-primary">
              <option>English</option>
              <option>Spanish</option>
              <option>French</option>
              <option>German</option>
            </select>
          </div>
          
          <div>
            <label className="block text-sm font-medium text-theme-primary mb-2">Date Format</label>
            <select className="w-full px-3 py-2 border border-theme rounded-lg bg-theme-background text-theme-primary focus:ring-2 focus:ring-theme-interactive-primary focus:border-theme-interactive-primary">
              <option>MM/DD/YYYY</option>
              <option>DD/MM/YYYY</option>
              <option>YYYY-MM-DD</option>
            </select>
          </div>
          
          <div>
            <label className="block text-sm font-medium text-theme-primary mb-2">Time Format</label>
            <select className="w-full px-3 py-2 border border-theme rounded-lg bg-theme-background text-theme-primary focus:ring-2 focus:ring-theme-interactive-primary focus:border-theme-interactive-primary">
              <option>12 Hour</option>
              <option>24 Hour</option>
            </select>
          </div>
          
          <div>
            <label className="block text-sm font-medium text-theme-primary mb-2">Currency</label>
            <select className="w-full px-3 py-2 border border-theme rounded-lg bg-theme-background text-theme-primary focus:ring-2 focus:ring-theme-interactive-primary focus:border-theme-interactive-primary">
              <option>USD ($)</option>
              <option>EUR (€)</option>
              <option>GBP (£)</option>
              <option>JPY (¥)</option>
            </select>
          </div>
          
          <div>
            <label className="block text-sm font-medium text-theme-primary mb-2">Timezone</label>
            <select className="w-full px-3 py-2 border border-theme rounded-lg bg-theme-background text-theme-primary focus:ring-2 focus:ring-theme-interactive-primary focus:border-theme-interactive-primary">
              <option>Eastern Time (US & Canada)</option>
              <option>Central Time (US & Canada)</option>
              <option>Mountain Time (US & Canada)</option>
              <option>Pacific Time (US & Canada)</option>
              <option>UTC</option>
            </select>
          </div>
        </div>
        
        <div className="mt-6 space-y-4">
          <div className="flex items-center justify-between p-4 bg-theme-background rounded-lg">
            <div>
              <h3 className="font-medium text-theme-primary">Compact Mode</h3>
              <p className="text-sm text-theme-secondary">Use a more condensed layout</p>
            </div>
            <label className="relative inline-flex items-center cursor-pointer">
              <input type="checkbox" className="sr-only peer" />
              <div className="w-11 h-6 bg-theme-surface rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-theme-interactive-primary"></div>
            </label>
          </div>
          
          <div className="flex items-center justify-between p-4 bg-theme-background rounded-lg">
            <div>
              <h3 className="font-medium text-theme-primary">Animations</h3>
              <p className="text-sm text-theme-secondary">Enable interface animations</p>
            </div>
            <label className="relative inline-flex items-center cursor-pointer">
              <input type="checkbox" className="sr-only peer" defaultChecked />
              <div className="w-11 h-6 bg-theme-surface rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-theme-interactive-primary"></div>
            </label>
          </div>
        </div>
        
        <div className="flex justify-end space-x-3 mt-6">
          <button className="btn-theme btn-theme-secondary">Reset to Defaults</button>
          <button className="btn-theme btn-theme-primary">Save Preferences</button>
        </div>
      </div>
    </div>
  );
};

const NotificationsSection: React.FC = () => {
  return (
    <div className="space-y-6">
      <div className="bg-theme-surface rounded-lg p-6">
        <h2 className="text-xl font-semibold text-theme-primary mb-6">Notification Preferences</h2>
        <p className="text-theme-secondary mb-6">Control how and when you receive notifications</p>
        
        <div className="space-y-6">
          <div>
            <h3 className="text-lg font-medium text-theme-primary mb-4">Email Notifications</h3>
            <div className="space-y-4">
              <div className="flex items-center justify-between p-4 bg-theme-background rounded-lg">
                <div>
                  <h4 className="font-medium text-theme-primary">Account Activity</h4>
                  <p className="text-sm text-theme-secondary">Notifications about your account activity</p>
                </div>
                <label className="relative inline-flex items-center cursor-pointer">
                  <input type="checkbox" className="sr-only peer" defaultChecked />
                  <div className="w-11 h-6 bg-theme-surface rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-theme-interactive-primary"></div>
                </label>
              </div>
              
              <div className="flex items-center justify-between p-4 bg-theme-background rounded-lg">
                <div>
                  <h4 className="font-medium text-theme-primary">Billing & Payments</h4>
                  <p className="text-sm text-theme-secondary">Invoice and payment notifications</p>
                </div>
                <label className="relative inline-flex items-center cursor-pointer">
                  <input type="checkbox" className="sr-only peer" defaultChecked />
                  <div className="w-11 h-6 bg-theme-surface rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-theme-interactive-primary"></div>
                </label>
              </div>
              
              <div className="flex items-center justify-between p-4 bg-theme-background rounded-lg">
                <div>
                  <h4 className="font-medium text-theme-primary">Security Alerts</h4>
                  <p className="text-sm text-theme-secondary">Important security notifications</p>
                </div>
                <label className="relative inline-flex items-center cursor-pointer">
                  <input type="checkbox" className="sr-only peer" defaultChecked />
                  <div className="w-11 h-6 bg-theme-surface rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-theme-interactive-primary"></div>
                </label>
              </div>
              
              <div className="flex items-center justify-between p-4 bg-theme-background rounded-lg">
                <div>
                  <h4 className="font-medium text-theme-primary">Marketing</h4>
                  <p className="text-sm text-theme-secondary">Product updates and promotions</p>
                </div>
                <label className="relative inline-flex items-center cursor-pointer">
                  <input type="checkbox" className="sr-only peer" />
                  <div className="w-11 h-6 bg-theme-surface rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-theme-interactive-primary"></div>
                </label>
              </div>
            </div>
          </div>
          
          <div>
            <h3 className="text-lg font-medium text-theme-primary mb-4">Push Notifications</h3>
            <div className="space-y-4">
              <div className="flex items-center justify-between p-4 bg-theme-background rounded-lg">
                <div>
                  <h4 className="font-medium text-theme-primary">Desktop Notifications</h4>
                  <p className="text-sm text-theme-secondary">Show desktop notifications</p>
                </div>
                <label className="relative inline-flex items-center cursor-pointer">
                  <input type="checkbox" className="sr-only peer" defaultChecked />
                  <div className="w-11 h-6 bg-theme-surface rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-theme-interactive-primary"></div>
                </label>
              </div>
              
              <div className="flex items-center justify-between p-4 bg-theme-background rounded-lg">
                <div>
                  <h4 className="font-medium text-theme-primary">Mobile Push</h4>
                  <p className="text-sm text-theme-secondary">Receive notifications on mobile devices</p>
                </div>
                <label className="relative inline-flex items-center cursor-pointer">
                  <input type="checkbox" className="sr-only peer" defaultChecked />
                  <div className="w-11 h-6 bg-theme-surface rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-theme-interactive-primary"></div>
                </label>
              </div>
            </div>
          </div>
          
          <div>
            <h3 className="text-lg font-medium text-theme-primary mb-4">Notification Schedule</h3>
            <div className="space-y-4">
              <div className="flex items-center justify-between p-4 bg-theme-background rounded-lg">
                <div>
                  <h4 className="font-medium text-theme-primary">Do Not Disturb</h4>
                  <p className="text-sm text-theme-secondary">Pause all notifications temporarily</p>
                </div>
                <label className="relative inline-flex items-center cursor-pointer">
                  <input type="checkbox" className="sr-only peer" />
                  <div className="w-11 h-6 bg-theme-surface rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-theme-interactive-primary"></div>
                </label>
              </div>
              
              <div className="p-4 bg-theme-background rounded-lg">
                <h4 className="font-medium text-theme-primary mb-3">Quiet Hours</h4>
                <div className="grid grid-cols-2 gap-4">
                  <div>
                    <label className="block text-sm text-theme-secondary mb-1">From</label>
                    <input type="time" defaultValue="22:00" className="w-full px-3 py-2 border border-theme rounded-lg bg-theme-background text-theme-primary" />
                  </div>
                  <div>
                    <label className="block text-sm text-theme-secondary mb-1">To</label>
                    <input type="time" defaultValue="08:00" className="w-full px-3 py-2 border border-theme rounded-lg bg-theme-background text-theme-primary" />
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
        
        <div className="flex justify-end space-x-3 mt-6">
          <button className="btn-theme btn-theme-secondary">Reset to Defaults</button>
          <button className="btn-theme btn-theme-primary">Save Preferences</button>
        </div>
      </div>
    </div>
  );
};

const SecuritySection: React.FC = () => {
  return (
    <div className="space-y-6">
      <div className="bg-theme-surface rounded-lg p-6">
        <h2 className="text-xl font-semibold text-theme-primary mb-6">Security Settings</h2>
        
        <div className="space-y-6">
          <div>
            <h3 className="text-lg font-medium text-theme-primary mb-4">Password</h3>
            <div className="bg-theme-background rounded-lg p-4">
              <div className="flex items-center justify-between mb-4">
                <div>
                  <p className="font-medium text-theme-primary">Current Password</p>
                  <p className="text-sm text-theme-secondary">Last changed 30 days ago</p>
                </div>
                <button className="btn-theme btn-theme-secondary">Change Password</button>
              </div>
              <div className="space-y-3">
                <div>
                  <label className="block text-sm font-medium text-theme-primary mb-1">Current Password</label>
                  <input type="password" className="w-full px-3 py-2 border border-theme rounded-lg bg-theme-background text-theme-primary" />
                </div>
                <div>
                  <label className="block text-sm font-medium text-theme-primary mb-1">New Password</label>
                  <input type="password" className="w-full px-3 py-2 border border-theme rounded-lg bg-theme-background text-theme-primary" />
                  <p className="text-xs text-theme-tertiary mt-1">Minimum 12 characters with uppercase, lowercase, numbers, and special characters</p>
                </div>
                <div>
                  <label className="block text-sm font-medium text-theme-primary mb-1">Confirm New Password</label>
                  <input type="password" className="w-full px-3 py-2 border border-theme rounded-lg bg-theme-background text-theme-primary" />
                </div>
              </div>
            </div>
          </div>
          
          <div>
            <h3 className="text-lg font-medium text-theme-primary mb-4">Two-Factor Authentication</h3>
            <div className="bg-theme-background rounded-lg p-4">
              <div className="flex items-center justify-between mb-4">
                <div>
                  <p className="font-medium text-theme-primary">2FA Status</p>
                  <p className="text-sm text-theme-secondary">Add an extra layer of security to your account</p>
                </div>
                <button className="btn-theme btn-theme-primary">Enable 2FA</button>
              </div>
              <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                <div className="p-3 border border-theme rounded-lg">
                  <h4 className="font-medium text-theme-primary mb-2">📱 Authenticator App</h4>
                  <p className="text-sm text-theme-secondary">Use an authenticator app like Google Authenticator or Authy</p>
                </div>
                <div className="p-3 border border-theme rounded-lg">
                  <h4 className="font-medium text-theme-primary mb-2">📧 Email</h4>
                  <p className="text-sm text-theme-secondary">Receive verification codes via email</p>
                </div>
              </div>
            </div>
          </div>
          
          <div>
            <h3 className="text-lg font-medium text-theme-primary mb-4">Active Sessions</h3>
            <div className="bg-theme-background rounded-lg p-4">
              <div className="space-y-3">
                <div className="flex items-center justify-between p-3 border border-theme rounded-lg">
                  <div className="flex items-center space-x-3">
                    <span className="text-2xl">💻</span>
                    <div>
                      <p className="font-medium text-theme-primary">Chrome on Windows</p>
                      <p className="text-sm text-theme-secondary">192.168.1.1 • Current session</p>
                    </div>
                  </div>
                  <span className="text-xs bg-theme-success bg-opacity-10 text-theme-success px-2 py-1 rounded">Active</span>
                </div>
                <div className="flex items-center justify-between p-3 border border-theme rounded-lg">
                  <div className="flex items-center space-x-3">
                    <span className="text-2xl">📱</span>
                    <div>
                      <p className="font-medium text-theme-primary">Safari on iPhone</p>
                      <p className="text-sm text-theme-secondary">203.0.113.0 • Last active 2 hours ago</p>
                    </div>
                  </div>
                  <button className="text-theme-error hover:text-theme-error-hover text-sm">Revoke</button>
                </div>
              </div>
              <button className="btn-theme btn-theme-secondary mt-4 w-full">Sign Out All Other Sessions</button>
            </div>
          </div>
          
          <div>
            <h3 className="text-lg font-medium text-theme-primary mb-4">Security Log</h3>
            <div className="bg-theme-background rounded-lg p-4">
              <div className="space-y-2">
                <div className="flex items-center justify-between py-2 border-b border-theme">
                  <div>
                    <p className="text-sm font-medium text-theme-primary">Password changed</p>
                    <p className="text-xs text-theme-secondary">March 15, 2024 at 10:30 AM</p>
                  </div>
                  <span className="text-xs text-theme-tertiary">192.168.1.1</span>
                </div>
                <div className="flex items-center justify-between py-2 border-b border-theme">
                  <div>
                    <p className="text-sm font-medium text-theme-primary">Login from new device</p>
                    <p className="text-xs text-theme-secondary">March 14, 2024 at 3:45 PM</p>
                  </div>
                  <span className="text-xs text-theme-tertiary">203.0.113.0</span>
                </div>
                <div className="flex items-center justify-between py-2">
                  <div>
                    <p className="text-sm font-medium text-theme-primary">2FA enabled</p>
                    <p className="text-xs text-theme-secondary">March 10, 2024 at 9:00 AM</p>
                  </div>
                  <span className="text-xs text-theme-tertiary">192.168.1.1</span>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};

const RolesPermissionsSection: React.FC = () => {
  const [activeTab, setActiveTab] = React.useState('roles');
  
  const systemRoles = [
    { name: 'Owner', users: 1, permissions: 'All permissions', system: true, color: 'purple' },
    { name: 'Admin', users: 2, permissions: 'Full access except ownership', system: true, color: 'blue' },
    { name: 'Manager', users: 3, permissions: 'User & content management', system: true, color: 'green' },
    { name: 'Support', users: 5, permissions: 'Customer support access', system: true, color: 'yellow' },
    { name: 'Viewer', users: 8, permissions: 'Read-only access', system: true, color: 'gray' },
  ];

  const customRoles = [
    { name: 'Finance Manager', users: 1, permissions: 'Billing & invoicing', system: false, color: 'indigo' },
    { name: 'Content Editor', users: 2, permissions: 'Content creation & editing', system: false, color: 'pink' },
  ];

  return (
    <div className="space-y-6">
      <div className="bg-theme-surface rounded-lg p-6">
        <div className="flex justify-between items-center mb-6">
          <div>
            <h2 className="text-xl font-semibold text-theme-primary">Roles & Permissions</h2>
            <p className="text-theme-secondary mt-1">Manage user roles and their associated permissions</p>
          </div>
          <button className="btn-theme btn-theme-primary">
            Create Role
          </button>
        </div>

        {/* Tab Navigation */}
        <div className="border-b border-theme mb-6">
          <nav className="-mb-px flex space-x-8">
            <button
              onClick={() => setActiveTab('roles')}
              className={`py-2 px-1 border-b-2 font-medium text-sm transition-colors duration-150 ${
                activeTab === 'roles'
                  ? 'border-theme-focus text-theme-link'
                  : 'border-transparent text-theme-tertiary hover:text-theme-primary hover:border-theme'
              }`}
            >
              Roles
            </button>
            <button
              onClick={() => setActiveTab('permissions')}
              className={`py-2 px-1 border-b-2 font-medium text-sm transition-colors duration-150 ${
                activeTab === 'permissions'
                  ? 'border-theme-focus text-theme-link'
                  : 'border-transparent text-theme-tertiary hover:text-theme-primary hover:border-theme'
              }`}
            >
              Permissions
            </button>
          </nav>
        </div>

        {/* Roles Tab */}
        {activeTab === 'roles' && (
          <div>
            <div className="mb-8">
          <h3 className="text-lg font-medium text-theme-primary mb-4">System Roles</h3>
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
            {systemRoles.map((role) => (
              <div key={role.name} className="bg-theme-background rounded-lg p-4 border border-theme">
                <div className="flex items-center justify-between mb-3">
                  <div className="flex items-center space-x-2">
                    <div className={`w-2 h-2 rounded-full ${
                      role.color === 'purple' ? 'bg-purple-500' :
                      role.color === 'blue' ? 'bg-blue-500' :
                      role.color === 'green' ? 'bg-green-500' :
                      role.color === 'yellow' ? 'bg-yellow-500' :
                      role.color === 'gray' ? 'bg-gray-500' :
                      role.color === 'indigo' ? 'bg-indigo-500' :
                      role.color === 'pink' ? 'bg-pink-500' :
                      'bg-theme-tertiary'
                    }`} />
                    <h4 className="font-medium text-theme-primary">{role.name}</h4>
                  </div>
                  <span className="text-xs bg-theme-surface px-2 py-1 rounded text-theme-tertiary">
                    System
                  </span>
                </div>
                <p className="text-sm text-theme-secondary mb-2">{role.permissions}</p>
                <div className="flex items-center justify-between text-sm">
                  <span className="text-theme-tertiary">{role.users} users</span>
                  <button className="text-theme-link hover:text-theme-link-hover">
                    View Details
                  </button>
                </div>
              </div>
            ))}
          </div>
        </div>

        <div>
          <h3 className="text-lg font-medium text-theme-primary mb-4">Custom Roles</h3>
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
            {customRoles.map((role) => (
              <div key={role.name} className="bg-theme-background rounded-lg p-4 border border-theme">
                <div className="flex items-center justify-between mb-3">
                  <div className="flex items-center space-x-2">
                    <div className={`w-2 h-2 rounded-full ${
                      role.color === 'purple' ? 'bg-purple-500' :
                      role.color === 'blue' ? 'bg-blue-500' :
                      role.color === 'green' ? 'bg-green-500' :
                      role.color === 'yellow' ? 'bg-yellow-500' :
                      role.color === 'gray' ? 'bg-gray-500' :
                      role.color === 'indigo' ? 'bg-indigo-500' :
                      role.color === 'pink' ? 'bg-pink-500' :
                      'bg-theme-tertiary'
                    }`} />
                    <h4 className="font-medium text-theme-primary">{role.name}</h4>
                  </div>
                  <span className="text-xs bg-theme-interactive-primary bg-opacity-10 text-theme-interactive-primary px-2 py-1 rounded">
                    Custom
                  </span>
                </div>
                <p className="text-sm text-theme-secondary mb-2">{role.permissions}</p>
                <div className="flex items-center justify-between text-sm">
                  <span className="text-theme-tertiary">{role.users} users</span>
                  <div className="flex space-x-2">
                    <button className="text-theme-link hover:text-theme-link-hover">
                      Edit
                    </button>
                    <button className="text-theme-error hover:text-theme-error-hover">
                      Delete
                    </button>
                  </div>
                </div>
              </div>
            ))}
          </div>
        </div>
          </div>
        )}

        {/* Permissions Tab */}
        {activeTab === 'permissions' && (
          <div>
            <PermissionsContent />
          </div>
        )}
      </div>
    </div>
  );
};

const PermissionsContent: React.FC = () => {
  const permissionGroups = [
    {
      name: 'User Management',
      permissions: [
        { name: 'user_view', label: 'View Users', description: 'Can view user profiles and lists' },
        { name: 'user_create', label: 'Create Users', description: 'Can create new user accounts' },
        { name: 'user_edit', label: 'Edit Users', description: 'Can modify user information' },
        { name: 'user_delete', label: 'Delete Users', description: 'Can remove user accounts' },
      ]
    },
    {
      name: 'Billing & Subscriptions',
      permissions: [
        { name: 'billing_view', label: 'View Billing', description: 'Can view billing information' },
        { name: 'billing_manage', label: 'Manage Billing', description: 'Can process payments and refunds' },
        { name: 'subscription_manage', label: 'Manage Subscriptions', description: 'Can modify subscription plans' },
        { name: 'invoice_create', label: 'Create Invoices', description: 'Can generate and send invoices' },
      ]
    },
    {
      name: 'System Administration',
      permissions: [
        { name: 'settings_view', label: 'View Settings', description: 'Can view system settings' },
        { name: 'settings_manage', label: 'Manage Settings', description: 'Can modify system configuration' },
        { name: 'audit_view', label: 'View Audit Logs', description: 'Can access system audit trails' },
        { name: 'api_manage', label: 'Manage API Keys', description: 'Can create and revoke API keys' },
      ]
    },
  ];

  return (
    <>
      {permissionGroups.map((group, index) => (
        <div key={group.name} className={index > 0 ? "mt-8" : ""}>
          <h3 className="text-lg font-medium text-theme-primary mb-4">{group.name}</h3>
          <div className="bg-theme-background rounded-lg overflow-hidden">
            <table className="w-full">
              <thead className="bg-theme-surface border-b border-theme">
                <tr>
                  <th className="text-left py-3 px-4 text-sm font-medium text-theme-primary">Permission</th>
                  <th className="text-left py-3 px-4 text-sm font-medium text-theme-primary">Description</th>
                  <th className="text-center py-3 px-4 text-sm font-medium text-theme-primary">Status</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-theme">
                {group.permissions.map((permission) => (
                  <tr key={permission.name} className="hover:bg-theme-surface-hover">
                    <td className="py-3 px-4">
                      <div>
                        <p className="font-medium text-theme-primary">{permission.label}</p>
                        <p className="text-xs text-theme-tertiary font-mono">{permission.name}</p>
                      </div>
                    </td>
                    <td className="py-3 px-4 text-sm text-theme-secondary">
                      {permission.description}
                    </td>
                    <td className="py-3 px-4 text-center">
                      <label className="relative inline-flex items-center cursor-pointer">
                        <input type="checkbox" className="sr-only peer" defaultChecked />
                        <div className="w-11 h-6 bg-theme-surface rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-theme-interactive-primary"></div>
                      </label>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      ))}
    </>
  );
};

const InvitationsPage: React.FC = () => {
  const pendingInvitations = [
    { email: 'john.doe@example.com', role: 'Manager', invitedBy: 'Admin User', sentAt: '2024-03-10', status: 'pending' },
    { email: 'jane.smith@example.com', role: 'Support', invitedBy: 'Admin User', sentAt: '2024-03-09', status: 'pending' },
  ];

  const acceptedInvitations = [
    { email: 'mike.wilson@example.com', role: 'Admin', invitedBy: 'Owner', sentAt: '2024-03-05', acceptedAt: '2024-03-06' },
    { email: 'sarah.jones@example.com', role: 'Viewer', invitedBy: 'Manager', sentAt: '2024-03-01', acceptedAt: '2024-03-01' },
  ];

  return (
    <div className="space-y-6">
      <div className="bg-theme-surface rounded-lg p-6">
        <div className="flex justify-between items-center mb-6">
          <div>
            <h2 className="text-xl font-semibold text-theme-primary">User Invitations</h2>
            <p className="text-theme-secondary mt-1">Manage invitations sent to new users</p>
          </div>
          <button className="btn-theme btn-theme-primary">
            Send Invitation
          </button>
        </div>

        <div className="mb-8">
          <h3 className="text-lg font-medium text-theme-primary mb-4">Pending Invitations</h3>
          <div className="bg-theme-background rounded-lg overflow-hidden">
            <table className="w-full">
              <thead className="bg-theme-surface border-b border-theme">
                <tr>
                  <th className="text-left py-3 px-4 text-sm font-medium text-theme-primary">Email</th>
                  <th className="text-left py-3 px-4 text-sm font-medium text-theme-primary">Role</th>
                  <th className="text-left py-3 px-4 text-sm font-medium text-theme-primary">Invited By</th>
                  <th className="text-left py-3 px-4 text-sm font-medium text-theme-primary">Sent</th>
                  <th className="text-left py-3 px-4 text-sm font-medium text-theme-primary">Actions</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-theme">
                {pendingInvitations.map((invitation) => (
                  <tr key={invitation.email} className="hover:bg-theme-surface-hover">
                    <td className="py-3 px-4 text-theme-primary">{invitation.email}</td>
                    <td className="py-3 px-4">
                      <span className="text-sm bg-theme-interactive-primary bg-opacity-10 text-theme-interactive-primary px-2 py-1 rounded">
                        {invitation.role}
                      </span>
                    </td>
                    <td className="py-3 px-4 text-theme-secondary">{invitation.invitedBy}</td>
                    <td className="py-3 px-4 text-theme-secondary">{invitation.sentAt}</td>
                    <td className="py-3 px-4">
                      <div className="flex space-x-2">
                        <button className="text-theme-link hover:text-theme-link-hover text-sm">
                          Resend
                        </button>
                        <button className="text-theme-error hover:text-theme-error-hover text-sm">
                          Cancel
                        </button>
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>

        <div>
          <h3 className="text-lg font-medium text-theme-primary mb-4">Accepted Invitations</h3>
          <div className="bg-theme-background rounded-lg overflow-hidden">
            <table className="w-full">
              <thead className="bg-theme-surface border-b border-theme">
                <tr>
                  <th className="text-left py-3 px-4 text-sm font-medium text-theme-primary">Email</th>
                  <th className="text-left py-3 px-4 text-sm font-medium text-theme-primary">Role</th>
                  <th className="text-left py-3 px-4 text-sm font-medium text-theme-primary">Invited By</th>
                  <th className="text-left py-3 px-4 text-sm font-medium text-theme-primary">Accepted</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-theme">
                {acceptedInvitations.map((invitation) => (
                  <tr key={invitation.email} className="hover:bg-theme-surface-hover">
                    <td className="py-3 px-4 text-theme-primary">{invitation.email}</td>
                    <td className="py-3 px-4">
                      <span className="text-sm bg-theme-success bg-opacity-10 text-theme-success px-2 py-1 rounded">
                        {invitation.role}
                      </span>
                    </td>
                    <td className="py-3 px-4 text-theme-secondary">{invitation.invitedBy}</td>
                    <td className="py-3 px-4 text-theme-secondary">{invitation.acceptedAt}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </div>
  );
};

const DelegationsPage: React.FC = () => {
  return <DelegationsManagement />;
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
          Manage your profile, users, accounts, roles, and permissions.
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
          <Route path="/settings" element={<SettingsPage />} />
          <Route path="/users" element={<UsersPage />} />
          <Route path="/invitations" element={<InvitationsPage />} />
          <Route path="/delegations" element={<DelegationsPage />} />
        </Routes>
      </div>
    </div>
  );
};

export default AccountManagementPage;