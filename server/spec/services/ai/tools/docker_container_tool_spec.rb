# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Tools::DockerContainerTool do
  let(:account) { create(:account) }
  let(:tool) { described_class.new(account: account) }

  describe "docker_create_container — OCI runtime (L0 isolation consumption)" do
    let(:host) { double("DockerHost") }
    let(:manager) { instance_double(Devops::Docker::ContainerManager) }

    before do
      allow(tool).to receive(:resolve_host).and_return(host)
      allow(Devops::Docker::ContainerManager).to receive(:new).and_return(manager)
    end

    it "routes the container through the OCI runtime via HostConfig.Runtime" do
      captured = nil
      allow(manager).to receive(:create_container) do |name:, image:, params:|
        captured = params
        { "Id" => "abc123" }
      end

      r = tool.execute(params: { action: "docker_create_container", name: "x", image: "img", runtime: "runsc" })

      expect(r[:success]).to be true
      expect(captured.dig(:HostConfig, :Runtime)).to eq("runsc")
    end

    it "preserves an existing HostConfig while setting the runtime" do
      captured = nil
      allow(manager).to receive(:create_container) do |name:, image:, params:|
        captured = params
        { "Id" => "abc" }
      end

      tool.execute(params: {
                     action: "docker_create_container", name: "x", image: "img", runtime: "runsc",
                     params: { "HostConfig" => { "Binds" => [ "/data:/data" ] } }
                   })

      expect(captured[:HostConfig][:Runtime]).to eq("runsc")
      expect(captured[:HostConfig]["Binds"]).to eq([ "/data:/data" ])
    end

    it "omits HostConfig.Runtime when no runtime is given" do
      captured = nil
      allow(manager).to receive(:create_container) do |name:, image:, params:|
        captured = params
        { "Id" => "abc" }
      end

      tool.execute(params: { action: "docker_create_container", name: "x", image: "img" })

      expect(captured[:HostConfig]).to be_nil
    end
  end
end
