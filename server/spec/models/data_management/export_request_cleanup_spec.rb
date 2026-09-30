# frozen_string_literal: true

require "rails_helper"

# The archive is the subject's full personal-data export. cleanup_file! is
# best effort by design: the path can name a file on another host (missing) or
# one this process may not remove (EACCES on a shared tmp under another uid),
# and neither may fail the request that asked. The path is written by a worker
# principal, so only a regular file whose real path is inside the exports base
# is ever removed (IMP-bdd811725d38).
RSpec.describe DataManagement::ExportRequest, "#cleanup_file!" do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:export_request) { create(:data_management_export_request, :completed, account: account, user: user) }
  let(:tmp_root) { Dir.mktmpdir("export-cleanup") }
  let(:base) { File.join(tmp_root, "data_exports") }

  before do
    FileUtils.mkdir_p(base)
    allow(described_class).to receive(:exports_base).and_return(base)
  end

  after { FileUtils.rm_rf(tmp_root) }

  it "removes the archive and clears the path" do
    path = File.join(base, "export.json").tap { |p| File.write(p, "exported data") }
    export_request.update_column(:file_path, path)

    export_request.cleanup_file!

    expect(File.exist?(path)).to be false
    expect(export_request.reload.file_path).to be_nil
  end

  it "is a no-op when the path names nothing on this host" do
    export_request.update_column(:file_path, "/nonexistent/host/elsewhere.json")

    expect(export_request.cleanup_file!).to be_nil
    expect(export_request.reload.file_path).to eq("/nonexistent/host/elsewhere.json")
  end

  it "removes nothing outside the exports base, answering false and keeping the path" do
    path = File.join(tmp_root, "outside.json").tap { |p| File.write(p, "keep") }
    export_request.update_column(:file_path, path)
    allow(Rails.logger).to receive(:warn)

    expect(export_request.cleanup_file!).to be false

    expect(File.exist?(path)).to be true
    expect(export_request.reload.file_path).to eq(path)
    expect(Rails.logger).to have_received(:warn).with(a_string_including(export_request.id.to_s))
    expect(Rails.logger).not_to have_received(:warn).with(a_string_including(path))
  end

  it "removes neither a symlink inside the base nor what it points at" do
    outside = File.join(tmp_root, "outside.json").tap { |p| File.write(p, "keep") }
    link = File.join(base, "link.json").tap { |p| File.symlink(outside, p) }
    export_request.update_column(:file_path, link)

    expect(export_request.cleanup_file!).to be false

    expect(File.symlink?(link)).to be true
    expect(File.exist?(outside)).to be true
  end

  it "logs and answers false, keeping the path, when the archive cannot be removed" do
    path = File.join(base, "export.json").tap { |p| File.write(p, "exported data") }
    export_request.update_column(:file_path, path)
    allow(FileUtils).to receive(:rm_f)
    allow(Rails.logger).to receive(:warn)

    expect(export_request.cleanup_file!).to be false

    expect(export_request.reload.file_path).to eq(path)
    expect(Rails.logger).to have_received(:warn).with(a_string_including("could not remove", export_request.id.to_s))
  end
end
