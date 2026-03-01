# frozen_string_literal: true

class MigrateSerializedTextToJson < ActiveRecord::Migration[8.0]
  def up
    # Migrate Account.settings from text to json
    add_column :accounts, :settings_temp, :json, default: {}

    # Copy data from text to json column
    Account.reset_column_information
    Account.find_each do |account|
      settings_data = begin
        JSON.parse(account.settings_before_type_cast || '{}')
      rescue JSON::ParserError
        {}
      end
      account.update_column(:settings_temp, settings_data)
    end

    remove_column :accounts, :settings
    rename_column :accounts, :settings_temp, :settings

    # Migrate Plan columns from text to json
    add_column :plans, :features_temp, :json, default: {}
    add_column :plans, :limits_temp, :json, default: {}
    add_column :plans, :metadata_temp, :json, default: {}
    add_column :plans, :default_roles_temp, :json, default: []
    add_column :plans, :volume_discount_tiers_temp, :json, default: []

    # Copy data for Plan columns
    Plan.reset_column_information
    Plan.find_each do |plan|
      features_data = begin
        JSON.parse(plan.features_before_type_cast || '{}')
      rescue JSON::ParserError
        {}
      end
      limits_data = begin
        JSON.parse(plan.limits_before_type_cast || '{}')
      rescue JSON::ParserError
        {}
      end
      metadata_data = begin
        JSON.parse(plan.metadata_before_type_cast || '{}')
      rescue JSON::ParserError
        {}
      end
      default_roles_data = begin
        JSON.parse(plan.default_roles_before_type_cast || '[]')
      rescue JSON::ParserError
        []
      end
      volume_discount_tiers_data = begin
        JSON.parse(plan.volume_discount_tiers_before_type_cast || '[]')
      rescue JSON::ParserError
        []
      end

      plan.update_columns(
        features_temp: features_data,
        limits_temp: limits_data,
        metadata_temp: metadata_data,
        default_roles_temp: default_roles_data,
        volume_discount_tiers_temp: volume_discount_tiers_data
      )
    end

    # Remove old text columns and rename new ones
    remove_column :plans, :features
    remove_column :plans, :limits
    remove_column :plans, :metadata
    remove_column :plans, :default_roles
    remove_column :plans, :volume_discount_tiers

    rename_column :plans, :features_temp, :features
    rename_column :plans, :limits_temp, :limits
    rename_column :plans, :metadata_temp, :metadata
    rename_column :plans, :default_roles_temp, :default_roles
    rename_column :plans, :volume_discount_tiers_temp, :volume_discount_tiers

    # Migrate AuditLog columns from text to json
    add_column :audit_logs, :old_values_temp, :json
    add_column :audit_logs, :new_values_temp, :json
    add_column :audit_logs, :metadata_temp, :json, default: {}

    # Copy data for AuditLog columns
    AuditLog.reset_column_information
    AuditLog.find_each do |log|
      old_values_data = begin
        JSON.parse(log.old_values_before_type_cast || 'null')
      rescue JSON::ParserError
        nil
      end
      new_values_data = begin
        JSON.parse(log.new_values_before_type_cast || 'null')
      rescue JSON::ParserError
        nil
      end
      metadata_data = begin
        JSON.parse(log.metadata_before_type_cast || '{}')
      rescue JSON::ParserError
        {}
      end

      log.update_columns(
        old_values_temp: old_values_data,
        new_values_temp: new_values_data,
        metadata_temp: metadata_data
      )
    end

    remove_column :audit_logs, :old_values
    remove_column :audit_logs, :new_values
    remove_column :audit_logs, :metadata

    rename_column :audit_logs, :old_values_temp, :old_values
    rename_column :audit_logs, :new_values_temp, :new_values
    rename_column :audit_logs, :metadata_temp, :metadata

    # Migrate remaining models with text metadata/settings columns

    # InvoiceLineItem.metadata
    add_column :invoice_line_items, :metadata_temp, :json, default: {}
    InvoiceLineItem.reset_column_information
    InvoiceLineItem.find_each do |item|
      metadata_data = begin
        JSON.parse(item.metadata_before_type_cast || '{}')
      rescue JSON::ParserError
        {}
      end
      item.update_column(:metadata_temp, metadata_data)
    end
    remove_column :invoice_line_items, :metadata
    rename_column :invoice_line_items, :metadata_temp, :metadata

    # Invoice.metadata
    add_column :invoices, :metadata_temp, :json, default: {}
    Invoice.reset_column_information
    Invoice.find_each do |invoice|
      metadata_data = begin
        JSON.parse(invoice.metadata_before_type_cast || '{}')
      rescue JSON::ParserError
        {}
      end
      invoice.update_column(:metadata_temp, metadata_data)
    end
    remove_column :invoices, :metadata
    rename_column :invoices, :metadata_temp, :metadata

    # PaymentMethod.metadata
    add_column :payment_methods, :metadata_temp, :json, default: {}
    PaymentMethod.reset_column_information
    PaymentMethod.find_each do |method|
      metadata_data = begin
        JSON.parse(method.metadata_before_type_cast || '{}')
      rescue JSON::ParserError
        {}
      end
      method.update_column(:metadata_temp, metadata_data)
    end
    remove_column :payment_methods, :metadata
    rename_column :payment_methods, :metadata_temp, :metadata

    # Payment.metadata
    add_column :payments, :metadata_temp, :json, default: {}
    Payment.reset_column_information
    Payment.find_each do |payment|
      metadata_data = begin
        JSON.parse(payment.metadata_before_type_cast || '{}')
      rescue JSON::ParserError
        {}
      end
      payment.update_column(:metadata_temp, metadata_data)
    end
    remove_column :payments, :metadata
    rename_column :payments, :metadata_temp, :metadata

    # RevenueSnapshot.metadata
    add_column :revenue_snapshots, :metadata_temp, :json, default: {}
    RevenueSnapshot.reset_column_information
    RevenueSnapshot.find_each do |snapshot|
      metadata_data = begin
        JSON.parse(snapshot.metadata_before_type_cast || '{}')
      rescue JSON::ParserError
        {}
      end
      snapshot.update_column(:metadata_temp, metadata_data)
    end
    remove_column :revenue_snapshots, :metadata
    rename_column :revenue_snapshots, :metadata_temp, :metadata

    # Subscription.metadata
    add_column :subscriptions, :metadata_temp, :json, default: {}
    Subscription.reset_column_information
    Subscription.find_each do |subscription|
      metadata_data = begin
        JSON.parse(subscription.metadata_before_type_cast || '{}')
      rescue JSON::ParserError
        {}
      end
      subscription.update_column(:metadata_temp, metadata_data)
    end
    remove_column :subscriptions, :metadata
    rename_column :subscriptions, :metadata_temp, :metadata
  end

  def down
    # Revert Account.settings from json to text
    add_column :accounts, :settings_temp, :text, default: '{}'
    Account.reset_column_information
    Account.find_each do |account|
      settings_json = (account.settings || {}).to_json
      account.update_column(:settings_temp, settings_json)
    end
    remove_column :accounts, :settings
    rename_column :accounts, :settings_temp, :settings

    # Revert Plan columns from json to text
    add_column :plans, :features_temp, :text, default: '{}'
    add_column :plans, :limits_temp, :text, default: '{}'
    add_column :plans, :metadata_temp, :text, default: '{}'
    add_column :plans, :default_roles_temp, :text
    add_column :plans, :volume_discount_tiers_temp, :text, default: '[]'

    Plan.reset_column_information
    Plan.find_each do |plan|
      plan.update_columns(
        features_temp: (plan.features || {}).to_json,
        limits_temp: (plan.limits || {}).to_json,
        metadata_temp: (plan.metadata || {}).to_json,
        default_roles_temp: (plan.default_roles || []).to_json,
        volume_discount_tiers_temp: (plan.volume_discount_tiers || []).to_json
      )
    end

    remove_column :plans, :features
    remove_column :plans, :limits
    remove_column :plans, :metadata
    remove_column :plans, :default_roles
    remove_column :plans, :volume_discount_tiers

    rename_column :plans, :features_temp, :features
    rename_column :plans, :limits_temp, :limits
    rename_column :plans, :metadata_temp, :metadata
    rename_column :plans, :default_roles_temp, :default_roles
    rename_column :plans, :volume_discount_tiers_temp, :volume_discount_tiers

    # Continue reverting other models...
    # (Additional rollback code would go here for other models)
  end
end
