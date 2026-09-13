# frozen_string_literal: true

module Powernode
  module Seeds
    # Seeds site settings ONE AT A TIME, so a failing setting can neither abort
    # the seed run nor hide the settings after it.
    #
    # db/seeds.rb used to wrap every setting in ONE shared begin/rescue. The
    # rescue itself is load-bearing — a blank contact_email once raised
    # RecordInvalid there and crash-looped fresh hub installs — but because it
    # was shared, the first `SiteSetting.set` to fail (it calls save!) silently
    # skipped every setting seeded after it. Here each setting gets its own
    # rescue: the failure is logged with the setting's key and error class,
    # collected, and named in the summary line #finish prints. Nothing is ever
    # re-raised, which is what keeps the crash-loop fix intact.
    class SiteSettingSeeder
      attr_reader :failed_keys

      def initialize(store: ::SiteSetting, out: $stdout)
        @store = store
        @out = out
        @failed_keys = []
      end

      # Writes the setting unconditionally (SiteSetting.set semantics).
      def set(key, value, **options)
        guard(key) { @store.set(key, value, **options) }
      end

      # Writes the setting only when no row exists, so a re-run of the seed
      # never reverts an operator's value back to the default.
      def set_unless_exists(key, value, **options)
        guard(key) { @store.set(key, value, **options) unless @store.exists?(key: key.to_s) }
      end

      def finish
        if @failed_keys.empty?
          @out.puts "✅ Created #{@store.count} site settings"
        else
          @out.puts "  ⚠️  #{@failed_keys.size} site setting(s) failed and were skipped: " \
                    "#{@failed_keys.join(', ')} — every other setting was seeded; continuing"
        end
        @failed_keys
      end

      private

      def guard(key)
        yield
      rescue StandardError => e
        @failed_keys << key.to_s
        Rails.logger.error("[seeds] site setting #{key} failed: #{e.class}: #{e.message}")
        nil
      end
    end
  end
end
