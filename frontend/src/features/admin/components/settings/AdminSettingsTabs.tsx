// Admin Settings Tabbed Interface
import React from 'react';
import { useLocation, useNavigate } from 'react-router-dom';
import { useSelector } from 'react-redux';
import { 
  CreditCard, Mail, Gauge, 
  LayoutDashboard, ShieldAlert, 
  Network, Lock
} from 'lucide-react';
import { RootState } from '@/shared/services';
import { hasPermissions } from '@/shared/utils/permissionUtils';

interface AdminSettingsTab {
  id: string;
  label: string;
  href: string;
  icon: React.ComponentType<any>;
  description: string;
  requiredPermissions?: string[];
}

const adminSettingsTabs: AdminSettingsTab[] = [
  {
    id: 'overview',
    label: 'Overview',
    href: '/app/admin/settings',
    icon: LayoutDashboard,
    description: 'System overview and quick admin actions'
    // No specific permissions required - covered by parent admin.settings.read
  },
  {
    id: 'payment-gateways',
    label: 'Payment Gateways',
    href: '/app/admin/settings/payment-gateways',
    icon: CreditCard,
    description: 'Configure Stripe, PayPal, and other payment providers',
    requiredPermissions: ['admin.billing.manage_gateways']
  },
  {
    id: 'email',
    label: 'Email Settings',
    href: '/app/admin/settings/email',
    icon: Mail,
    description: 'Configure email providers and delivery settings',
    requiredPermissions: ['admin.settings.email']
  },
  {
    id: 'proxy',
    label: 'Reverse Proxy',
    href: '/app/admin/settings/proxy',
    icon: Network,
    description: 'Configure reverse proxy URL handling and trusted hosts',
    requiredPermissions: ['admin.settings.read'] // Using basic admin settings permission
  },
  {
    id: 'security',
    label: 'Security',
    href: '/app/admin/settings/security',
    icon: Lock,
    description: 'Security policies and access controls',
    requiredPermissions: ['admin.settings.security']
  },
  {
    id: 'rate-limiting',
    label: 'Rate Limiting',
    href: '/app/admin/settings/rate-limiting',
    icon: ShieldAlert,
    description: 'Configure API rate limits and monitor usage patterns',
    requiredPermissions: ['admin.settings.security']
  },
  {
    id: 'performance',
    label: 'Performance',
    href: '/app/admin/settings/performance',
    icon: Gauge,
    description: 'Monitor and optimize system performance',
    requiredPermissions: ['admin.settings.read'] // Basic permission for now
  }
];

interface AdminSettingsTabsProps {
  className?: string;
}

export const AdminSettingsTabs: React.FC<AdminSettingsTabsProps> = ({ className = '' }) => {
  const location = useLocation();
  const navigate = useNavigate();
  const { user } = useSelector((state: RootState) => state.auth);

  // Filter tabs based on user permissions
  const availableTabs = adminSettingsTabs.filter(tab => {
    if (!tab.requiredPermissions || tab.requiredPermissions.length === 0) {
      return true; // No specific permissions required
    }
    return hasPermissions(user, tab.requiredPermissions);
  });

  // Determine active tab based on current path
  const getActiveTab = (): string => {
    const currentPath = location.pathname;
    const activeTab = availableTabs.find(tab => 
      tab.href === currentPath || (currentPath.startsWith(tab.href) && tab.href !== '/app/admin/settings')
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
            {availableTabs.map((tab) => {
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
          {availableTabs.map((tab) => (
            <option key={tab.id} value={tab.id}>
              {tab.label}
            </option>
          ))}
        </select>
      </div>

      {/* Active Tab Description */}
      <div className="mt-4 mb-6">
        {(() => {
          const activeTab = availableTabs.find(tab => tab.id === activeTabId);
          if (!activeTab) return null;
          const IconComponent = activeTab.icon;
          
          return (
            <div className="flex items-center gap-3">
              <div className="relative">
                <div className="absolute inset-0 bg-gradient-to-br from-theme-interactive-primary/15 to-theme-interactive-primary/5 rounded-lg blur-md"></div>
                <div className="relative p-2.5 bg-theme-surface/50 backdrop-blur-sm rounded-lg">
                  <IconComponent className="w-6 h-6 text-theme-interactive-primary" strokeWidth={1.5} />
                </div>
              </div>
              <div>
                <p className="text-theme-secondary">{activeTab.description}</p>
              </div>
            </div>
          );
        })()}
      </div>
    </div>
  );
};

export default AdminSettingsTabs;