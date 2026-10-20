# frozen_string_literal: true

require "rails_helper"

# Static guard for Account#destroy!: every table with a foreign key (no
# ON DELETE CASCADE/NULLIFY) onto a table that account teardown deletes must
# itself be deleted -- or nullified on that column -- by the teardown, or the
# final DELETE fails. The teardown retries a failing dependent after the others
# (declaration order is irrelevant), so only COVERAGE is asserted here, not order.
# Covers every loaded model, extension models included.
RSpec.describe "Account teardown FK coverage" do
  def models
    Rails.application.eager_load!
    ActiveRecord::Base.descendants.reject(&:abstract_class?).select { |m| (m.table_exists? rescue false) }
  end

  def klass_of(reflection)
    return nil if reflection.polymorphic?

    reflection.klass
  rescue NameError, ArgumentError
    nil
  end

  # Returns [deleted_tables, nullified [table, column] pairs, restrict_guarded tables]
  def teardown_closure
    deleted = Set.new(%w[accounts users audit_logs])
    nullified = Set.new
    guarded = Set.new
    queue = [Account, User]
    seen = Set.new
    until queue.empty?
      model = queue.shift
      next unless seen.add?(model)

      # A HABTM join table is cleaned by Rails when the owner row is destroyed.
      model.reflect_on_all_associations(:has_and_belongs_to_many).each { |r| deleted << r.join_table }
      model.reflect_on_all_associations.each do |r|
        next if r.options[:through]

        k = klass_of(r) or next
        case r.options[:dependent]
        when :destroy then deleted << k.table_name && queue << k
        when :delete_all then deleted << k.table_name
        when :nullify then nullified << [k.table_name, r.foreign_key.to_s]
        when :restrict_with_error, :restrict_with_exception then guarded << k.table_name
        end
      end
    end
    fks = ActiveRecord::Base.connection.tables.flat_map { |t| ActiveRecord::Base.connection.foreign_keys(t) }
    loop do
      more = fks.select { |f| deleted.include?(f.to_table) && f.on_delete == :cascade && !deleted.include?(f.from_table) }
      break if more.empty?

      more.each { |f| deleted << f.from_table }
    end
    [deleted, nullified, guarded, fks]
  end

  it "leaves no foreign key that would block the account DELETE" do
    deleted, nullified, guarded, fks = teardown_closure
    blockers = fks.select do |f|
      deleted.include?(f.to_table) && !%i[cascade nullify].include?(f.on_delete) &&
        !deleted.include?(f.from_table) && !guarded.include?(f.from_table) &&
        !nullified.include?([f.from_table, f.column.to_s])
    end
    expect(blockers.map { |f| "#{f.from_table}.#{f.column} -> #{f.to_table}" }.sort).to eq([])
  end
end
