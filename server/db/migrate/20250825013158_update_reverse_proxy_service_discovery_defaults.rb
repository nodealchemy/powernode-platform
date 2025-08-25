# frozen_string_literal: true

class UpdateReverseProxyServiceDiscoveryDefaults < ActiveRecord::Migration[7.2]
  def up
    # Update existing service discovery settings with complete defaults
    setting = AdminSetting.find_by(key: 'service_discovery_config')
    
    if setting.nil?
      # Create the setting with full defaults
      AdminSetting.create!(
        key: 'service_discovery_config',
        value: default_service_discovery_config.to_json,
        description: 'Service discovery configuration for auto-detecting services'
      )
    else
      # Merge existing configuration with new defaults
      existing_config = JSON.parse(setting.value) rescue {}
      merged_config = default_service_discovery_config.deep_merge(existing_config)
      setting.update!(value: merged_config.to_json)
    end
    
    puts "✅ Service discovery configuration updated with complete defaults"
  end

  def down
    # Revert to simple configuration
    setting = AdminSetting.find_by(key: 'service_discovery_config')
    if setting
      simple_config = {
        'enabled' => false,
        'methods' => [],
        'dns_config' => { 'enabled' => true, 'timeout' => 5 }
      }
      setting.update!(value: simple_config.to_json)
    end
    
    puts "⬇️ Service discovery configuration reverted to simple defaults"
  end

  private

  def default_service_discovery_config
    {
      'enabled' => false,
      'methods' => [],
      'dns_config' => {
        'enabled' => true,
        'timeout' => 5,
        'retries' => 3
      },
      'consul_config' => {
        'enabled' => false,
        'host' => 'localhost',
        'port' => 8500,
        'token' => nil,
        'datacenter' => 'dc1'
      },
      'port_scan_config' => {
        'enabled' => false,
        'port_ranges' => {
          'frontend' => [3000, 3010],
          'backend' => [5000, 5010],
          'worker' => [6000, 6010]
        },
        'timeout' => 5
      },
      'kubernetes_config' => {
        'enabled' => false,
        'namespace' => 'default',
        'label_selector' => 'app=service'
      }
    }
  end
end