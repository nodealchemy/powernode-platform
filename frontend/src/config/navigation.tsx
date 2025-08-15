// Navigation Configuration
import { 
  Home, BarChart3, Users, User, Settings, CreditCard, 
  FileText, Package, Wrench, UserCheck,
  HelpCircle, LogOut
} from 'lucide-react';
import { NavigationConfig } from '../types/navigation';

export const defaultNavigationConfig: NavigationConfig = {
  items: [
    {
      id: 'dashboard',
      name: 'Dashboard',
      href: '/dashboard',
      icon: Home,
      description: 'Overview and quick actions',
      permissions: ['dashboard_access'],
      order: 1
    },
    {
      id: 'profile',
      name: 'My Profile',
      href: '/dashboard/profile',
      icon: User,
      description: 'Personal information and preferences',
      permissions: ['dashboard_access'],
      order: 2
    }
  ],
  
  sections: [
    {
      id: 'business',
      name: 'Business',
      items: [
        {
          id: 'analytics',
          name: 'Analytics',
          href: '/dashboard/analytics',
          icon: BarChart3,
          description: 'Revenue and growth metrics',
          permissions: ['dashboard_access'],
          order: 1
        },
        {
          id: 'customers',
          name: 'Customers',
          href: '/dashboard/customers',
          icon: Users,
          description: 'Customer management and insights',
          permissions: ['dashboard_access'],
          order: 2
        },
        {
          id: 'subscriptions',
          name: 'Subscriptions',
          href: '/dashboard/subscriptions',
          icon: CreditCard,
          description: 'Subscription management and renewals',
          permissions: ['dashboard_access'],
          order: 3
        },
        {
          id: 'plans',
          name: 'Plans',
          href: '/dashboard/plans',
          icon: Package,
          description: 'Manage pricing and subscription tiers',
          permissions: ['plans_manage'],
          order: 4
        },
        {
          id: 'billing',
          name: 'Billing',
          href: '/dashboard/billing',
          icon: CreditCard,
          description: 'Invoices and payment processing',
          permissions: ['billing_access'],
          order: 5
        },
        {
          id: 'reports',
          name: 'Reports',
          href: '/dashboard/reports',
          icon: FileText,
          description: 'Financial and usage reports',
          permissions: ['reports_access'],
          order: 6
        }
      ],
      collapsible: true,
      defaultExpanded: true,
      order: 10
    },
    {
      id: 'content',
      name: 'Content',
      items: [
        {
          id: 'pages',
          name: 'Pages',
          href: '/dashboard/pages',
          icon: FileText,
          description: 'Manage content pages and documentation',
          permissions: ['dashboard_access'],
          roles: ['admin', 'owner'],
          order: 1
        }
      ],
      roles: ['admin', 'owner'],
      collapsible: true,
      defaultExpanded: true,
      order: 15
    }
  ],
  
  userMenuItems: [
    {
      id: 'profile',
      name: 'My Profile',
      href: '/dashboard/profile',
      icon: User,
      description: 'Personal information and preferences'
    },
    {
      id: 'account-settings',
      name: 'Account Settings',
      href: '/dashboard/settings',
      icon: Settings,
      description: 'Account configuration and security'
    },
    {
      id: 'billing-center',
      name: 'Billing Center',
      href: '/dashboard/billing',
      icon: CreditCard,
      description: 'Subscription and payment details'
    },
    {
      id: 'help-support',
      name: 'Help & Support',
      href: 'mailto:support@powernode.com',
      icon: HelpCircle,
      description: 'Get help and contact support',
      isExternal: true
    },
    {
      id: 'logout',
      name: 'Sign Out',
      href: '#logout',
      icon: LogOut,
      description: 'Sign out of your account'
    }
  ],
  
  quickActions: [
    {
      id: 'create-plan',
      name: 'Create Plan',
      href: '/dashboard/plans/new',
      icon: Package,
      description: 'Set up a new subscription plan'
    },
    {
      id: 'invite-team',
      name: 'Invite Team Member',
      href: '/dashboard/users',
      icon: UserCheck,
      description: 'Add someone to your team'
    },
    {
      id: 'view-analytics',
      name: 'View Analytics',
      href: '/dashboard/analytics',
      icon: BarChart3,
      description: 'Check your latest metrics'
    },
    {
      id: 'configure-payments',
      name: 'Configure Payments',
      href: '/dashboard/admin-settings/payment-gateways',
      icon: CreditCard,
      description: 'Set up payment processing',
      roles: ['admin', 'owner']
    }
  ]
};

// Admin-specific navigation overrides
export const adminNavigationOverrides = {
  sections: [
    {
      id: 'administration',
      name: 'Administration',
      items: [
        {
          id: 'workers',
          name: 'Workers',
          href: '/dashboard/workers',
          icon: Wrench,
          description: 'Manage background workers and job processing',
          roles: ['admin', 'owner'],
          order: 1
        },
        {
          id: 'settings',
          name: 'Settings',
          href: '/dashboard/admin-settings',
          icon: Settings,
          description: 'Platform configuration and settings',
          roles: ['admin', 'owner'],
          order: 2
        }
      ],
      roles: ['admin', 'owner'],
      collapsible: true,
      defaultExpanded: false,
      order: 20
    }
  ]
};

export default defaultNavigationConfig;