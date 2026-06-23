# frozen_string_literal: true

namespace :system do
  namespace :skills do
    desc "Generate system extension skill executor catalog from descriptor() methods"
    task generate_catalog: :environment do
      skills_dir = Rails.root.join(
        "..",
        "extensions/system/server/app/services/system/ai/skills"
      ).cleanpath

      unless skills_dir.directory?
        puts "Skills directory not found: #{skills_dir}"
        puts "(The system extension may be disabled or unmounted.)"
        exit 1
      end

      executor_paths = Dir[skills_dir.join("*_executor.rb")].sort
      executors      = []
      load_failures  = []
      repo_prefix    = "#{Rails.root.join('..').cleanpath}/"

      executor_paths.each do |path|
        class_basename = File.basename(path, ".rb").camelize
        begin
          klass = "System::Ai::Skills::#{class_basename}".constantize
        rescue NameError => e
          load_failures << { path: path.sub(repo_prefix, ""), error: "#{e.class}: #{e.message}" }
          next
        end

        # Skip the abstract base class — it intentionally raises from
        # `.descriptor` (it has no skill_descriptor of its own) and is a
        # superclass, not a real skill. Matching `*_executor.rb` sweeps it in.
        next if klass == ::System::Ai::Skills::BaseSkillExecutor

        unless klass.respond_to?(:descriptor)
          load_failures << { path: path.sub(repo_prefix, ""), error: "no .descriptor class method" }
          next
        end

        begin
          descriptor = klass.descriptor
        rescue StandardError, NotImplementedError => e
          load_failures << { path: path.sub(repo_prefix, ""), error: "descriptor raised #{e.class}: #{e.message}" }
          next
        end

        executors << descriptor.merge(
          executor_class: klass.name,
          source_path: path.sub(repo_prefix, "")
        )
      end

      # Markdown building (incl. GFM anchor slugging) lives in SystemSkillsCatalog
      # so it is unit-tested independently of loading the extension.
      markdown = SystemSkillsCatalog.render(
        executors: executors,
        load_failures: load_failures,
        generated_at: Time.current.strftime("%Y-%m-%d %H:%M UTC")
      )

      output_path = Rails.root.join(
        "..",
        "extensions/system/docs/SKILL_EXECUTOR_CATALOG.md"
      ).cleanpath
      FileUtils.mkdir_p(File.dirname(output_path))
      File.write(output_path, markdown)

      puts "Generated catalog for #{executors.size} executors across #{SystemSkillsCatalog.category_count(executors)} categories"
      puts "Output: #{output_path}"
      puts "Skipped: #{load_failures.size} executor file(s)" if load_failures.any?
    end
  end
end
