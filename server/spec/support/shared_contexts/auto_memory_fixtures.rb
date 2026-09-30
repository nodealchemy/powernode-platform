# frozen_string_literal: true

require "tmpdir"

# SYNTHETIC auto-memory fixtures. Nothing here reads the real memory directory,
# the real deployment-identifiers list, or the real private-extension names: the
# identifier pattern, the "private" names and every note body are invented.
RSpec.shared_context "auto memory fixtures" do
  let(:memory_dir) { Dir.mktmpdir("memory") }
  let(:scratch_dir) { Dir.mktmpdir("scratch") }
  let(:manifest_dir) { File.join(scratch_dir, "manifest") }
  let(:identifiers_file) { File.join(scratch_dir, "identifiers.txt") }
  let(:synthetic_private_names) { [ "quokkaworks" ] }
  # Text that MUST never surface in a report, a manifest or the rake output.
  let(:identifier_marker) { "ZQID-4471" }
  let(:private_marker) { "quokkaworks" }
  let(:sensitive_marker) { "break-glass" }

  before do
    File.write(identifiers_file, "# synthetic list\n\nZQID-[0-9]+\n")
    allow(Ai::Memory::EmbeddingService).to receive(:new)
      .and_return(instance_double(Ai::Memory::EmbeddingService, generate: nil))
  end

  after do
    FileUtils.remove_entry(memory_dir) if File.exist?(memory_dir)
    FileUtils.remove_entry(scratch_dir) if File.exist?(scratch_dir)
  end

  def write_memory(slug, body: "Body text.", name: slug, description: "About #{slug}", type: "project",
                   extra_front: nil, dir: memory_dir)
    front = +"---\nname: #{name}\ndescription: #{description}\nmetadata:\n  type: #{type}\n#{extra_front}---\n"
    File.write(File.join(dir, "#{slug}.md"), "#{front}\n#{body}\n")
  end
end
