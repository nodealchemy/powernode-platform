# frozen_string_literal: true

require "rails_helper"

# The archive is the subject's full personal-data export. cleanup_file! is
# best effort by design: the path can name a file on another host (missing) or
# one this process may not remove (EACCES on a shared tmp under another uid),
# and neither may fail the request that asked.
RSpec.describe DataManagement::ExportRequest, "#cleanup_file!" do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:export_request) { create(:data_management_export_request, :completed, account: account, user: user) }

  it "removes the archive and clears the path" do
    file = Tempfile.new("export-cleanup")
    file.close
    export_request.update_column(:file_path, file.path)

    export_request.cleanup_file!

    expect(File.exist?(file.path)).to be false
    expect(export_request.reload.file_path).to be_nil
  ensure
    file&.unlink
  end

  it "is a no-op when the path names nothing on this host" do
    export_request.update_column(:file_path, "/nonexistent/host/elsewhere.json")

    expect(export_request.cleanup_file!).to be_nil
    expect(export_request.reload.file_path).to eq("/nonexistent/host/elsewhere.json")
  end

  it "logs and answers false, keeping the path, when the archive cannot be removed" do
    file = Tempfile.new("export-cleanup-eacces")
    file.close
    export_request.update_column(:file_path, file.path)
    allow(File).to receive(:delete).and_call_original
    allow(File).to receive(:delete).with(file.path).and_raise(Errno::EACCES)
    allow(Rails.logger).to receive(:warn)

    expect(export_request.cleanup_file!).to be false

    expect(export_request.reload.file_path).to eq(file.path)
    expect(Rails.logger).to have_received(:warn).with(a_string_including("could not remove", "Errno::EACCES"))
  ensure
    file&.unlink
  end
end
