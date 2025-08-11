// Mock data service for development and fallback scenarios
import { User, UserStats } from './usersApi';
import { Account, AccountStats } from './accountsApi';

export class MockDataService {
  // Generate mock users
  static generateMockUsers(count: number = 10): User[] {
    const roles = ['owner', 'admin', 'billing_manager', 'customer_manager', 'support', 'analyst', 'user', 'viewer'];
    const statuses = ['active', 'suspended', 'inactive'];
    const mockUsers: User[] = [];

    for (let i = 0; i < count; i++) {
      const firstName = this.getRandomFirstName();
      const lastName = this.getRandomLastName();
      const email = `${firstName.toLowerCase()}.${lastName.toLowerCase()}@example.com`;
      const status = statuses[Math.floor(Math.random() * statuses.length)] as 'active' | 'suspended' | 'inactive';
      
      mockUsers.push({
        id: `user-${i + 1}`,
        first_name: firstName,
        last_name: lastName,
        full_name: `${firstName} ${lastName}`,
        email: email,
        email_verified: Math.random() > 0.2, // 80% verified
        phone: Math.random() > 0.5 ? `+1-555-${String(Math.floor(Math.random() * 10000)).padStart(4, '0')}` : undefined,
        roles: [roles[Math.floor(Math.random() * roles.length)]],
        status: status,
        locked: Math.random() > 0.9, // 10% locked
        failed_login_attempts: Math.floor(Math.random() * 3),
        last_login_at: Math.random() > 0.3 ? new Date(Date.now() - Math.random() * 30 * 24 * 60 * 60 * 1000).toISOString() : null,
        created_at: new Date(Date.now() - Math.random() * 365 * 24 * 60 * 60 * 1000).toISOString(),
        updated_at: new Date(Date.now() - Math.random() * 30 * 24 * 60 * 60 * 1000).toISOString(),
        preferences: {},
        account: {
          id: 'account-1',
          name: 'Acme Corporation',
          status: 'active'
        }
      });
    }

    return mockUsers;
  }

  // Generate mock user stats
  static generateMockUserStats(): UserStats {
    const totalUsers = 156;
    const activeUsers = Math.floor(totalUsers * 0.85);
    const suspendedUsers = Math.floor(totalUsers * 0.05);
    const unverifiedUsers = Math.floor(totalUsers * 0.1);
    
    return {
      total_users: totalUsers,
      active_users: activeUsers,
      suspended_users: suspendedUsers,
      unverified_users: unverifiedUsers,
      recent_logins: Math.floor(activeUsers * 0.6)
    };
  }

  // Generate mock accounts
  static generateMockAccounts(count: number = 5): Account[] {
    const statuses = ['active', 'suspended', 'cancelled'];
    const mockAccounts: Account[] = [];

    for (let i = 0; i < count; i++) {
      const companyName = this.getRandomCompanyName();
      const subdomain = companyName.toLowerCase().replace(/[^a-z0-9]/g, '').substring(0, 10) + (i + 1);
      const status = statuses[Math.floor(Math.random() * statuses.length)] as 'active' | 'suspended' | 'cancelled';
      
      mockAccounts.push({
        id: `account-${i + 1}`,
        name: companyName,
        subdomain: subdomain,
        status: status,
        owner_id: `user-${i + 1}`,
        users_count: Math.floor(Math.random() * 50) + 1,
        billing_email: `billing@${subdomain}.com`,
        phone: `+1-555-${String(Math.floor(Math.random() * 10000)).padStart(4, '0')}`,
        timezone: this.getRandomTimezone(),
        created_at: new Date(Date.now() - Math.random() * 365 * 24 * 60 * 60 * 1000).toISOString(),
        updated_at: new Date(Date.now() - Math.random() * 30 * 24 * 60 * 60 * 1000).toISOString(),
        subscription: Math.random() > 0.2 ? {
          id: `sub-${i + 1}`,
          plan_name: this.getRandomPlanName(),
          status: 'active',
          current_period_start: new Date(Date.now() - Math.random() * 30 * 24 * 60 * 60 * 1000).toISOString(),
          current_period_end: new Date(Date.now() + Math.random() * 30 * 24 * 60 * 60 * 1000).toISOString(),
          trial_end: Math.random() > 0.8 ? new Date(Date.now() + 14 * 24 * 60 * 60 * 1000).toISOString() : null
        } : undefined,
        owner: {
          id: `user-${i + 1}`,
          full_name: `${this.getRandomFirstName()} ${this.getRandomLastName()}`,
          email: `owner@${subdomain}.com`
        },
        settings: {}
      });
    }

    return mockAccounts;
  }

  // Generate mock account stats
  static generateMockAccountStats(): AccountStats {
    const totalAccounts = 1247;
    const activeAccounts = Math.floor(totalAccounts * 0.82);
    const suspendedAccounts = Math.floor(totalAccounts * 0.03);
    const trialAccounts = Math.floor(totalAccounts * 0.15);
    const payingAccounts = totalAccounts - trialAccounts;
    
    return {
      total_accounts: totalAccounts,
      active_accounts: activeAccounts,
      suspended_accounts: suspendedAccounts,
      trial_accounts: trialAccounts,
      paying_accounts: payingAccounts,
      total_mrr: Math.floor(payingAccounts * 7900) // Average $79/month
    };
  }

  // Get current account mock
  static getCurrentAccount(): Account {
    return {
      id: 'current-account',
      name: 'Your Company',
      subdomain: 'yourcompany',
      status: 'active',
      owner_id: 'current-user',
      users_count: 12,
      billing_email: 'billing@yourcompany.com',
      phone: '+1-555-0123',
      timezone: 'America/New_York',
      created_at: new Date(Date.now() - 180 * 24 * 60 * 60 * 1000).toISOString(),
      updated_at: new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString(),
      subscription: {
        id: 'current-sub',
        plan_name: 'Professional',
        status: 'active',
        current_period_start: new Date(Date.now() - 15 * 24 * 60 * 60 * 1000).toISOString(),
        current_period_end: new Date(Date.now() + 15 * 24 * 60 * 60 * 1000).toISOString(),
        trial_end: null
      },
      owner: {
        id: 'current-user',
        full_name: 'John Doe',
        email: 'john@yourcompany.com'
      },
      settings: {
        notifications: true,
        analytics: true
      }
    };
  }

  // Helper methods for generating random data
  private static getRandomFirstName(): string {
    const names = [
      'John', 'Jane', 'Michael', 'Sarah', 'David', 'Emily', 'Chris', 'Jessica', 
      'Daniel', 'Ashley', 'James', 'Amanda', 'Robert', 'Lisa', 'William', 'Melissa',
      'Richard', 'Kimberly', 'Joseph', 'Donna', 'Thomas', 'Carol', 'Charles', 'Ruth',
      'Christopher', 'Sharon', 'Matthew', 'Michelle', 'Anthony', 'Laura'
    ];
    return names[Math.floor(Math.random() * names.length)];
  }

  private static getRandomLastName(): string {
    const names = [
      'Smith', 'Johnson', 'Williams', 'Brown', 'Jones', 'Garcia', 'Miller', 'Davis',
      'Rodriguez', 'Martinez', 'Hernandez', 'Lopez', 'Gonzalez', 'Wilson', 'Anderson',
      'Thomas', 'Taylor', 'Moore', 'Jackson', 'Martin', 'Lee', 'Perez', 'Thompson',
      'White', 'Harris', 'Sanchez', 'Clark', 'Ramirez', 'Lewis', 'Robinson'
    ];
    return names[Math.floor(Math.random() * names.length)];
  }

  private static getRandomCompanyName(): string {
    const adjectives = ['Global', 'Advanced', 'Dynamic', 'Innovative', 'Strategic', 'Digital', 'Smart', 'Future'];
    const nouns = ['Solutions', 'Systems', 'Technologies', 'Enterprises', 'Industries', 'Corp', 'Inc', 'LLC'];
    const adj = adjectives[Math.floor(Math.random() * adjectives.length)];
    const noun = nouns[Math.floor(Math.random() * nouns.length)];
    return `${adj} ${noun}`;
  }

  private static getRandomPlanName(): string {
    const plans = ['Starter', 'Professional', 'Enterprise', 'Premium', 'Business', 'Team'];
    return plans[Math.floor(Math.random() * plans.length)];
  }

  private static getRandomTimezone(): string {
    const timezones = [
      'UTC', 'America/New_York', 'America/Chicago', 'America/Denver', 'America/Los_Angeles',
      'Europe/London', 'Europe/Berlin', 'Europe/Paris', 'Asia/Tokyo', 'Asia/Shanghai'
    ];
    return timezones[Math.floor(Math.random() * timezones.length)];
  }
}

// Export convenience functions
export const mockUsers = MockDataService.generateMockUsers(25);
export const mockUserStats = MockDataService.generateMockUserStats();
export const mockAccounts = MockDataService.generateMockAccounts(15);
export const mockAccountStats = MockDataService.generateMockAccountStats();
export const currentAccount = MockDataService.getCurrentAccount();