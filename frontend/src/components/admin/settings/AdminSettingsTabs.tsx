// Admin Settings Tabbed Interface
import React from 'react';
import { useLocation, useNavigate } from 'react-router-dom';
import { 
  CreditCard, Webhook, Mail, Shield, 
  Wrench, Zap, BarChart3 
} from 'lucide-react';

interface AdminSettingsTab {
  id: string;
  label: string;
  href: string;
  icon: React.ComponentType<any>;
  description: string;
}

const adminSettingsTabs: AdminSettingsTab[] = [
  {
    id: 'overview',
    label: 'Overview',
    href: '/dashboard/admin-settings',
    icon: BarChart3,
    description: 'System overview and quick admin actions'
  },
  {
    id: 'payment-gateways',
    label: 'Payment Gateways',
    href: '/dashboard/admin-settings/payment-gateways',
    icon: CreditCard,
    description: 'Configure Stripe, PayPal, and other payment providers'
  },
  {
    id: 'webhooks',
    label: 'Webhooks',
    href: '/dashboard/admin-settings/webhooks',
    icon: Webhook,
    description: 'Manage webhook endpoints and event notifications'
  },
  {
    id: 'email',
    label: 'Email Settings',
    href: '/dashboard/admin-settings/email',
    icon: Mail,
    description: 'Configure email providers and delivery settings'
  },
  {
    id: 'security',
    label: 'Security',
    href: '/dashboard/admin-settings/security',
    icon: Shield,
    description: 'Security policies and access controls'
  },
  {
    id: 'maintenance',
    label: 'Maintenance',
    href: '/dashboard/admin-settings/maintenance',
    icon: Wrench,
    description: 'System health and maintenance windows'
  },
  {
    id: 'performance',
    label: 'Performance',
    href: '/dashboard/admin-settings/performance',
    icon: Zap,
    description: 'Monitor and optimize system performance'
  }
];

interface AdminSettingsTabsProps {
  className?: string;
}

export const AdminSettingsTabs: React.FC<AdminSettingsTabsProps> = ({ className = '' }) => {
  const location = useLocation();
  const navigate = useNavigate();

  // Determine active tab based on current path
  const getActiveTab = (): string => {
    const currentPath = location.pathname;
    const activeTab = adminSettingsTabs.find(tab => 
      tab.href === currentPath || (currentPath.startsWith(tab.href) && tab.href !== '/dashboard/admin-settings')
    );
    return activeTab?.id || 'overview';
  };

  const activeTabId = getActiveTab();

  const handleTabClick = (tab: AdminSettingsTab) => {
    navigate(tab.href);
  };

  return (
    <div className={`w-full ${className}`}>
      {/* Desktop Tabs */}
      <div className="hidden md:block">
        <div className="border-b border-theme">
          <nav className="-mb-px flex space-x-8" aria-label="Admin Settings">
            {adminSettingsTabs.map((tab) => {
              const isActive = activeTabId === tab.id;
              const IconComponent = tab.icon;
              
              return (
                <button
                  key={tab.id}
                  onClick={() => handleTabClick(tab)}
                  className={`group inline-flex items-center py-4 px-1 border-b-2 font-medium text-sm transition-colors duration-150 ${
                    isActive
                      ? 'border-theme-interactive-primary text-theme-interactive-primary'
                      : 'border-transparent text-theme-secondary hover:text-theme-primary hover:border-theme-tertiary'
                  }`}
                  aria-current={isActive ? 'page' : undefined}
                  title={tab.description}
                >
                  <IconComponent className={`w-5 h-5 mr-2 ${
                    isActive ? 'text-theme-interactive-primary' : 'text-theme-tertiary group-hover:text-theme-secondary'
                  }`} />
                  {tab.label}
                </button>
              );
            })}
          </nav>
        </div>
      </div>

      {/* Mobile Dropdown */}
      <div className="md:hidden">
        <label htmlFor="admin-settings-tab" className="sr-only">
          Select an admin settings tab
        </label>
        <select
          id="admin-settings-tab"
          name="admin-settings-tab"
          value={activeTabId}
          onChange={(e) => {
            const selectedTab = adminSettingsTabs.find(tab => tab.id === e.target.value);
            if (selectedTab) handleTabClick(selectedTab);
          }}
          className="block w-full rounded-md border-theme bg-theme-surface text-theme-primary shadow-sm focus:border-theme-interactive-primary focus:ring-theme-interactive-primary"
        >
          {adminSettingsTabs.map((tab) => (
            <option key={tab.id} value={tab.id}>
              {tab.label}
            </option>
          ))}
        </select>
      </div>

      {/* Active Tab Description */}
      <div className="mt-4 mb-6">
        {(() => {
          const activeTab = adminSettingsTabs.find(tab => tab.id === activeTabId);
          if (!activeTab) return null;
          
          return (
            <div className="flex items-center gap-3">
              <div className="p-2 bg-theme-interactive-primary bg-opacity-10 rounded-lg">
                <activeTab.icon className="w-5 h-5 text-theme-interactive-primary" />
              </div>
              <div>
                <h1 className="text-2xl font-bold text-theme-primary">{activeTab.label}</h1>
                <p className="text-theme-secondary mt-1">{activeTab.description}</p>
              </div>
            </div>
          );
        })()}
      </div>
    </div>
  );
};

export default AdminSettingsTabs;