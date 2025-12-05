# frozen_string_literal: true

class Api::V1::SiteSettingsController < ApplicationController
  before_action :authenticate_request, except: [:public_footer]
  before_action :require_admin_access, except: [:public_footer]
  before_action :set_site_setting, only: [:show, :update, :destroy]

  # GET /api/v1/public/footer (public endpoint)
  def public_footer
    begin
      footer_data = SiteSetting.public_footer_settings
      
      # Add defaults for missing settings
      defaults = {
        'site_name' => 'Powernode',
        'copyright_text' => 'All rights reserved.',
        'copyright_year' => Date.current.year.to_s,
        'footer_description' => 'Powerful subscription management platform designed to help businesses grow.'
      }
      
      footer_data = defaults.merge(footer_data)

      render_success({
        footer: footer_data
      })
    rescue => e
      Rails.logger.error "Footer API error: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")

      render_error("Failed to load footer data", status: :internal_server_error)
    end
  end

  # GET /api/v1/site_settings
  def index
    @settings = SiteSetting.all.order(:key)

    render_success({
      settings: @settings.map { |setting| setting_data(setting) },
      total_count: @settings.count
    })
  end

  # GET /api/v1/site_settings/footer
  def footer
    footer_settings = SiteSetting.footer_settings

    render_success({
      settings: footer_settings
    })
  end

  # GET /api/v1/site_settings/:id
  def show
    render_success({
      setting: detailed_setting_data(@site_setting)
    })
  end

  # POST /api/v1/site_settings
  def create
    @site_setting = SiteSetting.new(site_setting_params)

    if @site_setting.save
      # Log setting creation
      AuditLog.create!(
        user: current_user,
        account: current_user.account,
        action: 'create_site_setting',
        resource_type: 'SiteSetting',
        resource_id: @site_setting.id,
        source: 'admin_panel',
        ip_address: request.remote_ip,
        user_agent: request.user_agent,
        metadata: {
          setting_key: @site_setting.key,
          setting_type: @site_setting.setting_type
        }
      )

      render_success({
        setting: detailed_setting_data(@site_setting),
        message: "Setting created successfully"
      }, status: :created)
    else
      render_validation_error(@site_setting)
    end
  end

  # PUT /api/v1/site_settings/:id
  def update
    old_value = @site_setting.value
    
    if @site_setting.update(site_setting_params)
      # Log setting update
      AuditLog.create!(
        user: current_user,
        account: current_user.account,
        action: 'update_site_setting',
        resource_type: 'SiteSetting',
        resource_id: @site_setting.id,
        source: 'admin_panel',
        ip_address: request.remote_ip,
        user_agent: request.user_agent,
        old_values: { value: old_value },
        new_values: { value: @site_setting.value },
        metadata: {
          setting_key: @site_setting.key
        }
      )

      render_success({
        setting: detailed_setting_data(@site_setting),
        message: "Setting updated successfully"
      })
    else
      render_validation_error(@site_setting)
    end
  end

  # DELETE /api/v1/site_settings/:id
  def destroy
    # Log setting deletion before destroying
    AuditLog.create!(
      user: current_user,
      account: current_user.account,
      action: 'delete_site_setting',
      resource_type: 'SiteSetting',
      resource_id: @site_setting.id,
      source: 'admin_panel',
      ip_address: request.remote_ip,
      user_agent: request.user_agent,
      old_values: @site_setting.attributes,
      metadata: {
        setting_key: @site_setting.key
      }
    )

    if @site_setting.destroy
      render_success(
        message: "Setting deleted successfully"
      )
    else
      render_error("Failed to delete setting", status: :unprocessable_content)
    end
  end

  # PUT /api/v1/site_settings/bulk_update
  def bulk_update
    settings_params = params.require(:settings).permit!
    updated_settings = {}
    errors = []

    settings_params.each do |key, value|
      begin
        setting = SiteSetting.set(
          key,
          value[:value],
          description: value[:description],
          setting_type: value[:setting_type] || 'string',
          is_public: value[:is_public] || false
        )
        updated_settings[key] = setting.parsed_value
      rescue => e
        errors << "#{key}: #{e.message}"
      end
    end

    if errors.empty?
      # Log bulk update
      AuditLog.create!(
        user: current_user,
        account: current_user.account,
        action: 'bulk_update_site_settings',
        resource_type: 'SiteSetting',
        source: 'admin_panel',
        ip_address: request.remote_ip,
        user_agent: request.user_agent,
        metadata: {
          updated_keys: updated_settings.keys,
          settings_count: updated_settings.count
        }
      )

      render_success({
        settings: updated_settings,
        message: "#{updated_settings.count} settings updated successfully"
      })
    else
      render_error("Some settings failed to update: #{errors.join(', ')}", status: :unprocessable_content)
    end
  end

  private

  def set_site_setting
    @site_setting = SiteSetting.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render_error("Setting not found", status: :not_found)
  end

  def require_admin_access
    unless current_user.has_permission?('admin.access') || current_user.has_permission?('settings.manage')
      render_error("Permission denied: requires admin.access or settings.manage", status: :forbidden)
    end
  end

  def site_setting_params
    params.require(:site_setting).permit(:key, :value, :description, :setting_type, :is_public)
  end

  def setting_data(setting)
    {
      id: setting.id,
      key: setting.key,
      value: setting.value,
      parsed_value: setting.parsed_value,
      description: setting.description,
      setting_type: setting.setting_type,
      is_public: setting.is_public,
      created_at: setting.created_at,
      updated_at: setting.updated_at
    }
  end

  def detailed_setting_data(setting)
    setting_data(setting)
  end
end