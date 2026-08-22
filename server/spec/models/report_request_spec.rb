# frozen_string_literal: true

require "rails_helper"

RSpec.describe ReportRequest do
  let(:account) { create(:account) }
  let(:reports_dir) { Rails.root.join("tmp", "reports") }

  before { FileUtils.mkdir_p(reports_dir) }

  describe ".cleanup_old_requests" do
    def aged(age:, status: "completed", file: nil)
      request = create(:report_request, account: account, status: status, file_path: file)
      request.update_column(:created_at, age)
      request
    end

    it "is bounded on every call — it cannot delete an unbounded set in one pass" do
      5.times { aged(age: 90.days.ago) }

      summary = described_class.cleanup_old_requests(older_than: 30.days, limit: 2)

      expect(summary[:candidate_count]).to eq(5)
      expect(summary[:deleted_count]).to eq(2)
      expect(summary[:remaining_count]).to eq(3)
      expect(described_class.count).to eq(3)
    end

    it "treats a non-positive limit as 1 rather than as unbounded" do
      3.times { aged(age: 90.days.ago) }

      summary = described_class.cleanup_old_requests(older_than: 30.days, limit: 0)

      expect(summary[:deleted_count]).to eq(1)
      expect(described_class.count).to eq(2)
    end

    it "counts without deleting on a dry run" do
      aged(age: 90.days.ago)

      summary = described_class.cleanup_old_requests(older_than: 30.days, dry_run: true)

      expect(summary).to include(candidate_count: 1, deleted_count: 0, dry_run: true)
      expect(described_class.count).to eq(1)
    end

    it "leaves the artifact alone when the row itself fails to destroy" do
      path = reports_dir.join("kept_on_error.pdf").to_s
      File.write(path, "x")
      aged(age: 90.days.ago, file: path)
      allow_any_instance_of(described_class).to receive(:destroy).and_raise(ActiveRecord::RecordNotDestroyed)

      expect { described_class.cleanup_old_requests(older_than: 30.days) }
        .to raise_error(ActiveRecord::RecordNotDestroyed)

      expect(File.exist?(path)).to be true
    ensure
      FileUtils.rm_f(path)
    end

    it "deletes the oldest candidates first when bounded" do
      oldest = aged(age: 400.days.ago)
      middle = aged(age: 200.days.ago)
      newest_candidate = aged(age: 40.days.ago)

      described_class.cleanup_old_requests(older_than: 30.days, limit: 2)

      expect(described_class.pluck(:id)).to eq([newest_candidate.id])
      expect(described_class.where(id: [oldest.id, middle.id])).not_to exist
    end
  end

  describe "#delete_artifact_file" do
    it "removes an artifact inside the reports directory" do
      path = reports_dir.join("inside.pdf").to_s
      File.write(path, "x")
      request = create(:report_request, account: account, file_path: path)

      expect(request.delete_artifact_file).to be true
      expect(File.exist?(path)).to be false
    end

    # file_path is written by the worker over HTTP. An unguarded File.delete on
    # it is an arbitrary-file-deletion primitive.
    it "refuses to unlink a path outside the allowed reports directories" do
      outside = Rails.root.join("tmp", "not_a_report.txt").to_s
      File.write(outside, "keep me")
      request = create(:report_request, account: account, file_path: outside)

      expect(request.delete_artifact_file).to be false
      expect(File.exist?(outside)).to be true
    ensure
      FileUtils.rm_f(outside)
    end

    it "refuses a sibling directory whose name merely starts with an allowed root" do
      outside = Rails.root.join("tmp", "reports_sibling.txt").to_s
      File.write(outside, "keep me")
      request = create(:report_request, account: account, file_path: outside)

      expect(request.delete_artifact_file).to be false
      expect(File.exist?(outside)).to be true
    ensure
      FileUtils.rm_f(outside)
    end

    # Kills the "drop File.expand_path" mutant: this path passes a raw
    # start_with? check against the allowed root and still resolves outside it.
    it "refuses a path that escapes the allowed root via .. segments" do
      target = Rails.root.join("tmp", "escaped_target.txt").to_s
      File.write(target, "keep me")
      traversal = "#{reports_dir}/../escaped_target.txt"
      expect(traversal).to start_with(reports_dir.to_s)  # the guard's naive form would accept it
      request = create(:report_request, account: account, file_path: traversal)

      expect(request.delete_artifact_file).to be false
      expect(File.exist?(target)).to be true
    ensure
      FileUtils.rm_f(target)
    end

    it "is a no-op when no artifact was ever recorded" do
      request = create(:report_request, account: account, file_path: nil)

      expect(request.delete_artifact_file).to be false
    end
  end
end
