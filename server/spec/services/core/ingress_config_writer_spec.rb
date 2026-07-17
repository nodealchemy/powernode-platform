# frozen_string_literal: true

require "rails_helper"
require "tmpdir"
require "yaml"
require "openssl"

# Core::IngressConfigWriter — the core-mode ingress baseline + the
# ingress_certs/ingress_routers provider seam (docs/operations/
# reverse-proxy.md §7-8, campaign 019f3458 increment 8).
#
# The system extension is loaded in this app, so
# Powernode::ExtensionRegistry.provider(:ingress_certs/:ingress_routers)
# already resolves to Acme::TraefikConfigWriter in the ambient environment.
# Tests that need to exercise the "no provider" (pure core mode) branch stub
# `extension_writer` directly rather than mutating the global registry, so
# they can't leak state into other examples.
RSpec.describe Core::IngressConfigWriter, type: :service do
  let(:account) { create(:account) }
  let(:tmp_dynamic_dir) { Dir.mktmpdir("core-ingress-dynamic") }
  let(:tmp_cert_dir)    { Dir.mktmpdir("core-ingress-certs") }

  after do
    FileUtils.rm_rf(tmp_dynamic_dir) if Dir.exist?(tmp_dynamic_dir)
    FileUtils.rm_rf(tmp_cert_dir)    if Dir.exist?(tmp_cert_dir)
  end

  describe ".write_static_config!" do
    it "renders the baseline static config (entrypoints, file provider, no dashboard)" do
      out = described_class.write_static_config!(dynamic_dir: tmp_dynamic_dir,
                                                   output_path: File.join(tmp_dynamic_dir, "..", "traefik.yaml"))
      parsed = YAML.load_file(out)

      expect(parsed.dig("entryPoints", "web", "address")).to eq(":80")
      expect(parsed.dig("entryPoints", "web", "http", "redirections", "entryPoint", "scheme")).to eq("https")
      expect(parsed.dig("entryPoints", "websecure", "address")).to eq(":443")
      expect(parsed.dig("entryPoints", "websecure", "http", "middlewares")).to eq([ "pass-tls-client-cert@file" ])
      expect(parsed.dig("providers", "file", "directory")).to eq(tmp_dynamic_dir)
      expect(parsed.dig("providers", "file", "watch")).to be true
      expect(parsed.dig("api", "dashboard")).to be false
    end
  end

  describe ".render_services" do
    it "renders the 3 fixed upstreams" do
      services = described_class.render_services
      expect(services.keys).to contain_exactly("powernode-backend", "powernode-frontend", "powernode-worker-web")
      expect(services.dig("powernode-backend", "loadBalancer", "servers", 0, "url")).to eq(described_class.backend_url)
    end
  end

  describe ".extension_writer" do
    it "is nil when either provider facet is absent" do
      allow(::Powernode::ExtensionRegistry).to receive(:provider).with(:ingress_certs).and_return(Object.new)
      allow(::Powernode::ExtensionRegistry).to receive(:provider).with(:ingress_routers).and_return(nil)
      expect(described_class.extension_writer).to be_nil
    end

    it "is nil when the two facets resolve to different objects (unsupported topology)" do
      allow(::Powernode::ExtensionRegistry).to receive(:provider).with(:ingress_certs).and_return(Object.new)
      allow(::Powernode::ExtensionRegistry).to receive(:provider).with(:ingress_routers).and_return(Object.new)
      expect(described_class.extension_writer).to be_nil
    end

    it "returns the shared object when both facets resolve to the SAME registered writer" do
      writer = Object.new
      allow(::Powernode::ExtensionRegistry).to receive(:provider).with(:ingress_certs).and_return(writer)
      allow(::Powernode::ExtensionRegistry).to receive(:provider).with(:ingress_routers).and_return(writer)
      expect(described_class.extension_writer).to be(writer)
    end

    it "resolves the real system extension's Acme::TraefikConfigWriter in this app (ambient, unstubbed)" do
      expect(described_class.extension_writer).to eq(::Acme::TraefikConfigWriter)
    end
  end

  describe ".write! — provider delegation" do
    it "delegates the ENTIRE write to the registered extension writer when the seam is present" do
      fake_writer = Class.new do
        def self.write!(account:, dynamic_dir:, cert_dir:)
          { output_path: "fake/#{account.id}.yaml", cert_count: 99, dynamic_dir: dynamic_dir, cert_dir: cert_dir }
        end
      end
      allow(described_class).to receive(:extension_writer).and_return(fake_writer)

      result = described_class.write!(account: account, dynamic_dir: tmp_dynamic_dir, cert_dir: tmp_cert_dir)
      expect(result).to eq(
        output_path: "fake/#{account.id}.yaml", cert_count: 99, dynamic_dir: tmp_dynamic_dir, cert_dir: tmp_cert_dir
      )
    end

    it "falls back to the core baseline when no provider is registered (nil ⇒ core mode)" do
      allow(described_class).to receive(:extension_writer).and_return(nil)

      result = described_class.write!(account: account, dynamic_dir: tmp_dynamic_dir, cert_dir: tmp_cert_dir)
      expect(result[:cert_count]).to eq(1)
      expect(File.basename(result[:output_path])).to eq("acme-#{account.id}.yaml")
    end
  end

  describe "baseline shape (core mode, no provider registered)" do
    before { allow(described_class).to receive(:extension_writer).and_return(nil) }

    it "writes a self-signed cert entry + the 4 generic routers + the 3 services" do
      result = described_class.write!(account: account, dynamic_dir: tmp_dynamic_dir, cert_dir: tmp_cert_dir)
      parsed = YAML.load_file(result[:output_path])

      expect(parsed["tls"]["certificates"].size).to eq(1)
      cert_entry = parsed["tls"]["certificates"].first
      expect(File.exist?(cert_entry["certFile"])).to be true
      expect(File.exist?(cert_entry["keyFile"])).to be true
      expect(cert_entry["stores"]).to eq([ "default" ])

      router_keys = parsed["http"]["routers"].keys
      expect(router_keys.size).to eq(4)
      expect(router_keys).to all(satisfy { |k| k.end_with?("-api", "-agent", "-cable", "-frontend") })
      # None of the advanced (extension-only) routers ever appear in baseline mode.
      expect(router_keys).not_to include(satisfy { |k| k.include?("node-api") || k.include?("federation-api") ||
                                                        k.include?("worker-api") || k.include?("worker-auth") ||
                                                        k.include?("sidekiq") })

      expect(parsed["http"]["services"].keys)
        .to contain_exactly("powernode-backend", "powernode-frontend", "powernode-worker-web")
    end

    it "marks every baseline router as an HTTPS (tls) router so :443 serves it (imp 019f6c3d-aab2)" do
      result = described_class.write!(account: account, dynamic_dir: tmp_dynamic_dir, cert_dir: tmp_cert_dir)
      parsed = YAML.load_file(result[:output_path])

      parsed["http"]["routers"].each_value do |router|
        expect(router).to have_key("tls")
        expect(router["tls"]).to eq({})
        expect(router["entryPoints"]).to eq([ "websecure" ])
      end
    end

    it "generates a structurally valid self-signed cert/key pair" do
      described_class.write!(account: account, dynamic_dir: tmp_dynamic_dir, cert_dir: tmp_cert_dir)
      cert_path = described_class.baseline_cert_file_path(cert_dir: tmp_cert_dir)
      key_path  = described_class.baseline_key_file_path(cert_dir: tmp_cert_dir)

      cert = OpenSSL::X509::Certificate.new(File.read(cert_path))
      key  = OpenSSL::PKey.read(File.read(key_path))
      expect(cert.subject.to_s).to include(described_class.baseline_host)
      expect(key).to be_a(OpenSSL::PKey::RSA)
    end

    it "reuses the existing self-signed pair across calls (stable fingerprint, no per-boot rotation)" do
      first  = described_class.write!(account: account, dynamic_dir: tmp_dynamic_dir, cert_dir: tmp_cert_dir)
      cert_path = described_class.baseline_cert_file_path(cert_dir: tmp_cert_dir)
      first_pem = File.read(cert_path)

      second = described_class.write!(account: account, dynamic_dir: tmp_dynamic_dir, cert_dir: tmp_cert_dir)
      second_pem = File.read(cert_path)

      expect(second_pem).to eq(first_pem)
      expect(first[:output_path]).to eq(second[:output_path])
    end

    it "regenerates when the on-disk pair is invalid (corrupt/blank)" do
      described_class.write!(account: account, dynamic_dir: tmp_dynamic_dir, cert_dir: tmp_cert_dir)
      cert_path = described_class.baseline_cert_file_path(cert_dir: tmp_cert_dir)
      File.write(cert_path, "not a cert")

      described_class.write!(account: account, dynamic_dir: tmp_dynamic_dir, cert_dir: tmp_cert_dir)
      expect { OpenSSL::X509::Certificate.new(File.read(cert_path)) }.not_to raise_error
    end

    it "applies the host_rule_for host matcher (honors POWERNODE_PROXY_EXTRA_HOSTS)" do
      original = ENV["POWERNODE_PROXY_EXTRA_HOSTS"]
      begin
        ENV["POWERNODE_PROXY_EXTRA_HOSTS"] = "extra.example.test"
        allow(::AdminSetting).to receive(:reverse_proxy_url_config).and_return({})

        result = described_class.write!(account: account, dynamic_dir: tmp_dynamic_dir, cert_dir: tmp_cert_dir)
        parsed = YAML.load_file(result[:output_path])
        frontend_rule = parsed["http"]["routers"].values.find { |r| r["service"] == "powernode-frontend" }["rule"]
        expect(frontend_rule).to include("Host(`extra.example.test`)")
      ensure
        original.nil? ? ENV.delete("POWERNODE_PROXY_EXTRA_HOSTS") : (ENV["POWERNODE_PROXY_EXTRA_HOSTS"] = original)
      end
    end
  end

  describe ".ensure_host_login_ingress! (universal host front door)" do
    # The system extension IS loaded in this app, so the seam resolves to
    # Acme::TraefikConfigWriter — these examples prove the host login is
    # generated REGARDLESS (it never consults the seam), which is exactly the
    # extension-mode gap it closes.
    it "writes the dedicated 00-host-login.yaml with a self-signed cert + services" do
      result = described_class.ensure_host_login_ingress!(dynamic_dir: tmp_dynamic_dir, cert_dir: tmp_cert_dir)

      expect(File.basename(result[:output_path])).to eq("00-host-login.yaml")
      parsed = YAML.load_file(result[:output_path])

      cert_entry = parsed["tls"]["certificates"].first
      expect(File.exist?(cert_entry["certFile"])).to be true
      expect(File.exist?(cert_entry["keyFile"])).to be true
      expect(parsed["http"]["services"].keys)
        .to contain_exactly("powernode-backend", "powernode-frontend", "powernode-worker-web")
    end

    it "emits host-agnostic (PathPrefix-only, no Host()) TLS routers" do
      described_class.ensure_host_login_ingress!(dynamic_dir: tmp_dynamic_dir, cert_dir: tmp_cert_dir)
      parsed = YAML.load_file(File.join(tmp_dynamic_dir, "00-host-login.yaml"))
      routers = parsed["http"]["routers"]

      routers.each_value do |router|
        expect(router["rule"]).to start_with("PathPrefix(")
        expect(router["rule"]).not_to include("Host(")
        expect(router["tls"]).to eq({})
        expect(router["entryPoints"]).to eq([ "websecure" ])
      end
      # backend prefixes route to the app; the bare "/" catch-all to the frontend
      expect(routers["host-login-api"]["service"]).to eq("powernode-backend")
      expect(routers["host-login-up"]["service"]).to eq("powernode-backend")
      expect(routers["host-login-frontend"]["rule"]).to eq("PathPrefix(`/`)")
      expect(routers["host-login-frontend"]["service"]).to eq("powernode-frontend")
      expect(routers["host-login-sidekiq"]["service"]).to eq("powernode-worker-web")
    end

    it "is idempotent — reuses the persisted cert (stable fingerprint across reboots)" do
      described_class.ensure_host_login_ingress!(dynamic_dir: tmp_dynamic_dir, cert_dir: tmp_cert_dir)
      cert_path = described_class.baseline_cert_file_path(cert_dir: tmp_cert_dir)
      first_pem = File.read(cert_path)

      described_class.ensure_host_login_ingress!(dynamic_dir: tmp_dynamic_dir, cert_dir: tmp_cert_dir)
      expect(File.read(cert_path)).to eq(first_pem)
    end

    it "does NOT consult the extension seam (still writes when a provider is registered)" do
      # Even if the ACME writer is registered, the host login is produced.
      expect(described_class).not_to receive(:extension_writer)
      result = described_class.ensure_host_login_ingress!(dynamic_dir: tmp_dynamic_dir, cert_dir: tmp_cert_dir)
      expect(File.exist?(result[:output_path])).to be true
    end
  end

  describe "path resolution defaults" do
    around do |example|
      keys = %w[POWERNODE_TRAEFIK_DYNAMIC_DIR POWERNODE_TRAEFIK_CERT_DIR POWERNODE_TRAEFIK_CA_DIR POWERNODE_TRAEFIK_STATIC_CONFIG]
      originals = keys.index_with { |k| ENV[k] }
      keys.each { |k| ENV.delete(k) }
      example.run
    ensure
      originals.each { |k, v| v.nil? ? ENV.delete(k) : (ENV[k] = v) }
    end

    it "honors explicit env overrides" do
      ENV["POWERNODE_TRAEFIK_DYNAMIC_DIR"] = "/tmp/explicit-dynamic"
      expect(described_class.default_dynamic_dir).to eq("/tmp/explicit-dynamic")
    end

    it "falls back to a Rails.root/tmp/traefik/<env> path when /etc/traefik is unusable" do
      allow(described_class).to receive(:can_use_system_prefix?).and_return(false)
      expect(described_class.default_dynamic_dir).to include("tmp/traefik")
    end
  end

  # Worker mTLS: a co-located Sidekiq worker authenticates its backend calls by
  # presenting the agent-issued node cert; Traefik must request+verify it and
  # forward the CN. The host-login ingress carries clientAuth ONLY when this
  # node has enrolled (agent CA on disk); pure core mode is unchanged.
  describe "worker mTLS (host-login clientAuth + pass-tls-client-cert)" do
    around do |ex|
      orig = ENV["WORKER_PKI_DIR"]
      ex.run
    ensure
      orig.nil? ? ENV.delete("WORKER_PKI_DIR") : (ENV["WORKER_PKI_DIR"] = orig)
    end

    let(:ca_pem) do
      key  = OpenSSL::PKey::RSA.new(2048)
      name = OpenSSL::X509::Name.parse("/CN=Powernode Internal CA (test)")
      cert = OpenSSL::X509::Certificate.new
      cert.version = 2
      cert.serial  = 1
      cert.subject = name
      cert.issuer  = name
      cert.public_key = key.public_key
      cert.not_before = Time.now - 3600
      cert.not_after  = Time.now + 3600
      cert.sign(key, OpenSSL::Digest.new("SHA256"))
      cert.to_pem
    end

    it "always defines the pass-tls-client-cert middleware the websecure entrypoint references" do
      config = described_class.host_login_config("/c/crt", "/c/key")
      expect(config.dig("http", "middlewares", "pass-tls-client-cert"))
        .to eq("passTLSClientCert" => { "info" => { "subject" => { "commonName" => true } } })
    end

    it "omits clientAuth when no CA is supplied (pure core mode, unchanged)" do
      config = described_class.host_login_config("/c/crt", "/c/key")
      expect(config["tls"]).not_to have_key("options")
    end

    it "adds OPTIONAL clientAuth against the CA when supplied (enrolled node; login still works cert-less)" do
      config = described_class.host_login_config("/c/crt", "/c/key", client_auth_ca: "/certs/internal-ca.crt")
      opt = config.dig("tls", "options", "default", "clientAuth")
      expect(opt["clientAuthType"]).to eq("VerifyClientCertIfGiven")
      expect(opt["caFiles"]).to eq([ "/certs/internal-ca.crt" ])
    end

    it "ensure_host_login_ingress! copies the agent CA next to the serving cert + wires clientAuth" do
      pki = Dir.mktmpdir("agent-pki")
      File.write(File.join(pki, "ca-chain.crt"), ca_pem)
      ENV["WORKER_PKI_DIR"] = pki

      result = described_class.ensure_host_login_ingress!(dynamic_dir: tmp_dynamic_dir, cert_dir: tmp_cert_dir)
      expect(result[:client_auth_ca]).to eq(File.join(tmp_cert_dir, "internal-ca.crt"))
      expect(File.read(result[:client_auth_ca])).to eq(ca_pem)

      parsed = YAML.load_file(result[:output_path])
      expect(parsed.dig("tls", "options", "default", "clientAuth", "caFiles"))
        .to eq([ File.join(tmp_cert_dir, "internal-ca.crt") ])
    ensure
      FileUtils.rm_rf(pki) if pki
    end

    it "ensure_host_login_ingress! omits clientAuth when the agent CA is absent (pure core mode)" do
      ENV["WORKER_PKI_DIR"] = Dir.mktmpdir("empty-pki")
      result = described_class.ensure_host_login_ingress!(dynamic_dir: tmp_dynamic_dir, cert_dir: tmp_cert_dir)
      expect(result[:client_auth_ca]).to be_nil
      parsed = YAML.load_file(result[:output_path])
      expect(parsed["tls"]).not_to have_key("options")
    end
  end
end
