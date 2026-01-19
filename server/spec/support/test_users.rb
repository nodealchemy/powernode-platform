# frozen_string_literal: true

# Unified Test User Configuration
#
# This module provides a single source of truth for test user configuration,
# used by both FactoryBot factories and seeded demo users.
#
# Usage:
#   TestUsers::PASSWORD              # Standard test password
#   TestUsers::DOMAIN                # Email domain for test users
#   TestUsers.email_for('demo')      # => "demo@powernode.org"
#   TestUsers.demo                   # => { email: "demo@powernode.org", password: "..." }
#
module TestUsers
  # Standard strong password for factory-created test users
  # Meets password policy requirements: 16+ chars, mixed case, digits, symbols
  PASSWORD = 'TestP@ssw0rd2024!#'

  # Email domain for all test users (factory and seeded)
  DOMAIN = 'powernode.org'

  # Predefined test user configurations
  USERS = {
    demo: {
      email: "demo@#{DOMAIN}",
      name: 'Demo User',
      role: 'manager',
      description: 'Primary test user for smoke tests and E2E testing'
    },
    admin: {
      email: "admin@#{DOMAIN}",
      name: 'System Admin',
      role: 'super_admin',
      description: 'System administrator with full access'
    },
    manager: {
      email: "manager@#{DOMAIN}",
      name: 'Demo Manager',
      role: 'manager',
      description: 'Manager user for team and permission tests'
    },
    billing: {
      email: "billing@#{DOMAIN}",
      name: 'Billing Manager',
      role: 'billing_manager',
      description: 'Billing manager for billing and subscription tests'
    },
    member: {
      email: "member@#{DOMAIN}",
      name: 'Member User',
      role: 'member',
      description: 'Regular member for member-level permission tests'
    }
  }.freeze

  class << self
    # Generate email for a test user type
    def email_for(type)
      USERS.dig(type.to_sym, :email) || "#{type}@#{DOMAIN}"
    end

    # Get configuration for a specific user type
    def config_for(type)
      USERS[type.to_sym]
    end

    # Get demo user config (most common)
    def demo
      USERS[:demo]
    end

    def admin
      USERS[:admin]
    end

    def manager
      USERS[:manager]
    end

    def billing
      USERS[:billing]
    end

    def member
      USERS[:member]
    end

    # Generate a unique test email (for factory sequences)
    def unique_email(prefix = 'user', sequence_number = nil)
      seq = sequence_number || SecureRandom.hex(4)
      "#{prefix}#{seq}@#{DOMAIN}"
    end

    # Check if an email belongs to the test domain
    def test_email?(email)
      email&.end_with?("@#{DOMAIN}")
    end
  end
end
