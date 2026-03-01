# frozen_string_literal: true

module Ai
  module KnowledgePopulation
    # Reflects on the Rails application and file system to produce a structured
    # hash describing every model, route, service, controller, worker job,
    # and frontend feature in the platform.
    class ScannerService
      def initialize(project_root: nil)
        @project_root = Pathname.new(project_root || Rails.root.join(".."))
        @server_root = Rails.root
      end

      def scan!
        load_all_classes

        {
          models: scan_models,
          routes: scan_routes,
          services: scan_services,
          controllers: scan_controllers,
          jobs: scan_jobs,
          frontend_features: scan_frontend_features
        }
      end

      private

      # ================================================================
      # MODEL SCANNING (via ActiveRecord reflection)
      # ================================================================

      # Attempt full eager_load; on failure, individually load model files
      # so that AR descendants are populated even when unrelated files have
      # Zeitwerk naming issues.
      def load_all_classes
        begin
          Rails.application.eager_load!
          return
        rescue StandardError => e
          Rails.logger.warn("[KnowledgePopulation] Partial eager load (#{e.class}): #{e.message}")
        end

        # Fallback: resolve each model file via constantize (triggers Zeitwerk per-file)
        model_dirs = [
          @server_root.join("app/models"),
          @project_root.join("extensions/enterprise/server/app/models")
        ]

        model_dirs.each do |dir|
          next unless Dir.exist?(dir)

          Dir.glob(dir.join("**/*.rb")).sort.each do |file|
            relative = file.sub("#{dir}/", "")
            next if relative.start_with?("concerns/")

            class_name = relative.chomp(".rb").split("/").map(&:camelize).join("::")
            begin
              class_name.constantize
            rescue StandardError, LoadError
              # Skip files that fail to load
            end
          end
        end
      end

      def scan_models
        grouped = Hash.new { |h, k| h[k] = [] }

        ActiveRecord::Base.descendants.each do |model|
          next if model.abstract_class?
          next if model.name.blank?
          next unless safe_table_exists?(model)

          namespace = extract_namespace(model.name)
          grouped[namespace] << build_model_info(model)
        end

        grouped.transform_values { |models| models.sort_by { |m| m[:name] } }
      end

      def build_model_info(model)
        {
          name: model.name,
          table_name: model.table_name,
          primary_key: model.primary_key,
          columns: safe_columns(model),
          associations: safe_associations(model),
          validations: safe_validations(model)
        }
      end

      def safe_table_exists?(model)
        model.table_exists?
      rescue StandardError
        false
      end

      def extract_namespace(class_name)
        parts = class_name.split("::")
        parts.length > 1 ? parts[0..-2].join("::") : "Root"
      end

      def safe_columns(model)
        model.columns.map do |col|
          {
            name: col.name,
            type: col.type.to_s,
            null: col.null,
            default: col.default&.to_s
          }
        end
      rescue StandardError
        []
      end

      def safe_associations(model)
        model.reflect_on_all_associations.filter_map do |assoc|
          resolved_class = begin
            assoc.class_name
          rescue StandardError
            assoc.options[:class_name].to_s
          end

          {
            macro: assoc.macro.to_s,
            name: assoc.name.to_s,
            class_name: resolved_class,
            foreign_key: (assoc.foreign_key.to_s rescue nil),
            options: assoc.options.slice(:dependent, :through, :source, :polymorphic)
                          .transform_values(&:to_s)
          }
        rescue StandardError
          nil
        end
      end

      def safe_validations(model)
        model.validators.filter_map do |v|
          {
            kind: v.class.name.demodulize.underscore.gsub(/_validator$/, ""),
            attributes: v.attributes.map(&:to_s),
            options: v.options.except(:if, :unless, :on).transform_values(&:to_s)
          }
        rescue StandardError
          nil
        end
      end

      # ================================================================
      # ROUTE SCANNING (via Rails router)
      # ================================================================

      def scan_routes
        grouped = Hash.new { |h, k| h[k] = [] }

        Rails.application.routes.routes.each do |route|
          next if route.internal

          path = route.path.spec.to_s.gsub("(.:format)", "")
          verb = route.verb.to_s.presence || "ANY"
          reqs = route.requirements
          controller = reqs[:controller]
          action = reqs[:action]
          next unless controller.present? && action.present?

          ns = controller.split("/")[0..-2].join("/")
          ns = "root" if ns.blank?

          grouped[ns] << {
            verb: verb,
            path: path,
            controller: controller,
            action: action
          }
        end

        grouped
      end

      # ================================================================
      # FILE SYSTEM SCANNING (services, controllers, jobs, frontend)
      # ================================================================

      def scan_services
        scan_ruby_files(@server_root.join("app/services"))
      end

      def scan_controllers
        scan_ruby_files(@server_root.join("app/controllers"))
      end

      def scan_jobs
        scan_ruby_files(@project_root.join("worker/app/jobs"))
      end

      def scan_ruby_files(base_dir)
        grouped = Hash.new { |h, k| h[k] = [] }
        return grouped unless Dir.exist?(base_dir)

        Dir.glob(base_dir.join("**/*.rb")).sort.each do |file|
          relative = file.sub("#{base_dir}/", "")
          parts = relative.chomp(".rb").split("/")
          class_name = parts.map(&:camelize).join("::")
          namespace = parts.length > 1 ? parts[0..-2].map(&:camelize).join("::") : "Root"

          grouped[namespace] << { name: class_name, file: relative }
        end

        grouped
      end

      def scan_frontend_features
        features_dir = @project_root.join("frontend/src/features")
        return {} unless Dir.exist?(features_dir)

        result = {}

        Dir.children(features_dir).sort.each do |name|
          full = features_dir.join(name)
          next unless File.directory?(full)

          subdirs = Dir.children(full)
                       .select { |d| File.directory?(full.join(d)) }
                       .sort
          file_count = Dir.glob(full.join("**/*")).count { |f| File.file?(f) }

          result[name] = { subdirectories: subdirs, file_count: file_count }
        end

        result
      end
    end
  end
end
