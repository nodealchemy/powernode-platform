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
  # Everything lives under ONE root, and the writer's derived SIBLING paths
  # therefore stay inside it.
  #
  # These were previously two bare Dir.mktmpdir calls, i.e. directly in /tmp.
  # The writer mirrors the production layout by deriving siblings — traefik.yaml
  # beside the dynamic dir, and a durable `dynamic/` mirror beside the cert dir
  # — so those resolved to the SHARED /tmp/traefik.yaml and /tmp/dynamic. That
  # passes on a developer box and fails with Errno::EACCES on a freshly
  # provisioned one where /tmp/traefik.yaml is owned by another user (caught by
  # the two-machine parity run). The durable-mirror example also `rm -rf`'d
  # /tmp/dynamic on the way out, which is not this spec's directory to delete.
  #
  # `live` and `durable` are separate parents on purpose: in production the
  # dynamic dir is tmpfs-backed under /etc/traefik while the certs and their
  # durable mirror sit on /persist. Sharing one parent here would collapse the
  # live dynamic dir and the durable mirror onto the same path and stop the
  # mirroring assertion from testing anything.
  let(:tmp_root)        { Dir.mktmpdir("core-ingress") }
  let(:tmp_live_dir)    { File.join(tmp_root, "live").tap { |d| FileUtils.mkdir_p(d) } }
  let(:tmp_dynamic_dir) { File.join(tmp_live_dir, "dynamic").tap { |d| FileUtils.mkdir_p(d) } }
  let(:tmp_durable_dir) { File.join(tmp_root, "durable").tap { |d| FileUtils.mkdir_p(d) } }
  let(:tmp_cert_dir)    { File.join(tmp_durable_dir, "certs").tap { |d| FileUtils.mkdir_p(d) } }

  after { FileUtils.rm_rf(tmp_root) }

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

    # The durable mirror is what lets the reverse proxy start WITH clientAuth on
    # the next boot instead of ~2 minutes into it. /etc/traefik/dynamic is a
    # tmpfs-backed overlay on a module-composed node, so without this the config
    # is gone every boot and the proxy never asks for a client certificate until
    # Rails is up — which is what left the agent 401ing on a poisoned connection.
    it "mirrors the config next to the certs so it survives a boot" do
      result = described_class.ensure_host_login_ingress!(dynamic_dir: tmp_dynamic_dir, cert_dir: tmp_cert_dir)

      durable = result[:durable_path]
      expect(durable).to be_present
      # Sibling of the cert dir, derived — cert_dir is operator-configurable.
      expect(File.dirname(durable)).to eq(File.join(File.dirname(tmp_cert_dir), "dynamic"))
      expect(File.basename(durable)).to eq("00-host-login.yaml")
      expect(File.read(durable)).to eq(File.read(result[:output_path]))
      # Must be readable by the unprivileged proxy user that restores it.
      expect(format("%o", File.stat(durable).mode)[-3..]).to eq("644")
      # No ensure-block cleanup: the mirror now lands under tmp_root, which the
      # after-hook removes. It previously had to delete /tmp/dynamic by hand.
    end

    # Pre-seeding the NEXT boot must never break ingress on THIS one.
    it "still writes the live config when the durable mirror cannot be written" do
      allow(FileUtils).to receive(:cp).and_raise(Errno::EACCES, "read-only")

      result = described_class.ensure_host_login_ingress!(dynamic_dir: tmp_dynamic_dir, cert_dir: tmp_cert_dir)

      expect(result[:durable_path]).to be_nil
      expect(File.exist?(result[:output_path])).to be true
      expect(YAML.load_file(result[:output_path])["tls"]).to be_present
    end

    it "writes 00-host-login.yaml world-readable (0644) even under a restrictive umask" do
      # Regression: a leaked 0077 process umask previously made this NON-SECRET
      # file 0600, unreadable by the unprivileged traefik user → all :443 → 404.
      # The explicit chmod must defeat any ambient umask.
      old_umask = File.umask(0o077)
      begin
        result = described_class.ensure_host_login_ingress!(dynamic_dir: tmp_dynamic_dir, cert_dir: tmp_cert_dir)
        mode = File.stat(result[:output_path]).mode & 0o777
        expect(mode).to eq(0o644)
        # group- and world-readable (traefik is neither the owner nor in root's group).
        expect(mode & 0o044).to eq(0o044)
      ensure
        File.umask(old_umask)
      end
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

    # Regression: the pass-tls middleware must be applied at the ROUTER level, not
    # merely defined + left to the entrypoint. On a composed hub node the traefik
    # static config lacks the pass-tls-client-cert@file entrypoint reference, so
    # without the router-level middleware the CN is never forwarded and every
    # worker call 401s.
    #
    # SECURITY (imp 019f71e3-2a9c): Traefik v3.7.1's passTLSClientCert only
    # *overwrites* X-Forwarded-Tls-Client-Cert[-Info] when a client cert was
    # negotiated (it sets, never deletes) and clientAuth here is OPTIONAL
    # (VerifyClientCertIfGiven) — so a cert-less caller could forge the CN header
    # that Security::MtlsTrust#verify_request trusts on its no-PEM path. The
    # backend routers therefore ALWAYS carry an unconditional strip middleware
    # (removes any client-supplied forwarded-cert header) that runs BEFORE
    # pass-tls re-adds the proxy-authentic CN from the verified handshake cert.
    it "strips forged forwarded-cert headers, THEN forwards the verified CN, on backend routers when mTLS is on" do
      config = described_class.host_login_config("/c/crt", "/c/key", client_auth_ca: "/certs/internal-ca.crt")
      routers = config.dig("http", "routers")
      expect(routers["host-login-api"]["middlewares"]).to eq(%w[strip-forwarded-client-cert pass-tls-client-cert])
      expect(routers["host-login-up"]["middlewares"]).to eq(%w[strip-forwarded-client-cert pass-tls-client-cert])
      # the frontend catch-all router must NOT carry either middleware
      expect(routers["host-login-frontend"]).not_to have_key("middlewares")
    end

    it "STILL strips forged forwarded-cert headers on backend routers when mTLS is off (no CA) — no forgeable CN reaches the backend" do
      config = described_class.host_login_config("/c/crt", "/c/key")
      routers = config.dig("http", "routers")
      # No clientAuth ⇒ no CN is ever forwarded, but the strip must remain so a
      # forged X-Forwarded-Tls-Client-Cert-Info can't reach verify_request.
      expect(routers["host-login-api"]["middlewares"]).to eq(%w[strip-forwarded-client-cert])
      expect(routers["host-login-cable"]["middlewares"]).to eq(%w[strip-forwarded-client-cert])
      # neither the CN-forwarding middleware nor any middleware on non-backend routers
      expect(routers["host-login-api"]["middlewares"]).not_to include("pass-tls-client-cert")
      expect(routers["host-login-frontend"]).not_to have_key("middlewares")
      expect(routers["host-login-sidekiq"]).not_to have_key("middlewares")
    end

    it "defines the strip middleware to DELETE exactly the headers MtlsTrust consumes (empty value ⇒ Traefik Header.Del)" do
      config = described_class.host_login_config("/c/crt", "/c/key")
      strip = config.dig("http", "middlewares", "strip-forwarded-client-cert")
      expect(strip).to eq(
        "headers" => {
          "customRequestHeaders" => {
            Security::MtlsTrust::PEM_HEADER     => "",
            Security::MtlsTrust::SUBJECT_HEADER => ""
          }
        }
      )
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

    # DUAL-TRUST (task #13): a Vault-less hub signs node certs with its OWN
    # local internal CA (POWERNODE_CA_LOCAL_DIR/root.crt) yet still holds a
    # DEV-signed cert from its bootstrap enrollment. The client-auth bundle must
    # trust BOTH: the enrolled agent chain AND the hub's own local root.
    context "dual-trust client-auth bundle (enrolled agent CA + local internal-CA root)" do
      def build_ca_cert(cn)
        key  = OpenSSL::PKey.generate_key("ED25519")
        cert = OpenSSL::X509::Certificate.new
        cert.version = 2
        cert.serial  = SecureRandom.random_number(2**32)
        cert.subject = cert.issuer = OpenSSL::X509::Name.parse("/CN=#{cn}")
        cert.public_key = key
        cert.not_before = Time.now - 3600
        cert.not_after  = Time.now + 3600
        ef = OpenSSL::X509::ExtensionFactory.new(cert, cert)
        cert.add_extension(ef.create_extension("basicConstraints", "CA:TRUE", true))
        cert.add_extension(ef.create_extension("keyUsage", "keyCertSign, cRLSign", true))
        cert.sign(key, nil)
        [ key, cert ]
      end

      def sign_leaf(ca_key, ca_cert, cn)
        leaf_key = OpenSSL::PKey.generate_key("ED25519")
        leaf = OpenSSL::X509::Certificate.new
        leaf.version = 2
        leaf.serial  = SecureRandom.random_number(2**32)
        leaf.subject = OpenSSL::X509::Name.parse("/CN=#{cn}")
        leaf.issuer  = ca_cert.subject
        leaf.public_key = leaf_key
        leaf.not_before = Time.now - 60
        leaf.not_after  = Time.now + 3600
        leaf.sign(ca_key, nil)
        leaf
      end

      def store_from_bundle(bundle)
        store = OpenSSL::X509::Store.new
        bundle.scan(/-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----\n?/m).each do |block|
          store.add_cert(OpenSSL::X509::Certificate.new(block))
        end
        store
      end

      it "unions both CA roots and validates a leaf signed by the LOCAL CA" do
        _agent_key, agent_ca = build_ca_cert("Agent Enrollment CA (test)")
        local_key,  local_ca = build_ca_cert("Local Hub Internal CA (test)")
        agent_dir = Dir.mktmpdir("agent-pki")
        local_dir = Dir.mktmpdir("local-ca")
        File.write(File.join(agent_dir, "ca-chain.crt"), agent_ca.to_pem)
        File.write(File.join(local_dir, "root.crt"), local_ca.to_pem)
        ENV["WORKER_PKI_DIR"] = agent_dir
        ENV["POWERNODE_CA_LOCAL_DIR"] = local_dir

        result = described_class.ensure_host_login_ingress!(dynamic_dir: tmp_dynamic_dir, cert_dir: tmp_cert_dir)
        bundle = File.read(result[:client_auth_ca])

        expect(bundle).to include(agent_ca.to_pem.strip)
        expect(bundle).to include(local_ca.to_pem.strip)

        # A node cert THIS hub's local CA signs must pass against the bundle.
        leaf = sign_leaf(local_key, local_ca, "node-abc")
        expect(store_from_bundle(bundle).verify(leaf)).to be(true)

        # clientAuth still references the single emitted bundle file.
        parsed = YAML.load_file(result[:output_path])
        expect(parsed.dig("tls", "options", "default", "clientAuth", "caFiles"))
          .to eq([ result[:client_auth_ca] ])
      ensure
        ENV.delete("POWERNODE_CA_LOCAL_DIR")
        FileUtils.rm_rf(agent_dir) if agent_dir
        FileUtils.rm_rf(local_dir) if local_dir
      end

      it "deduplicates when the agent chain and local root are the SAME cert" do
        _key, ca = build_ca_cert("Shared CA (test)")
        agent_dir = Dir.mktmpdir("agent-pki")
        local_dir = Dir.mktmpdir("local-ca")
        File.write(File.join(agent_dir, "ca-chain.crt"), ca.to_pem)
        File.write(File.join(local_dir, "root.crt"), ca.to_pem)
        ENV["WORKER_PKI_DIR"] = agent_dir
        ENV["POWERNODE_CA_LOCAL_DIR"] = local_dir

        result = described_class.ensure_host_login_ingress!(dynamic_dir: tmp_dynamic_dir, cert_dir: tmp_cert_dir)
        bundle = File.read(result[:client_auth_ca])
        expect(bundle.scan("BEGIN CERTIFICATE").size).to eq(1)
      ensure
        ENV.delete("POWERNODE_CA_LOCAL_DIR")
        FileUtils.rm_rf(agent_dir) if agent_dir
        FileUtils.rm_rf(local_dir) if local_dir
      end

      # Per-source best-effort: an EXISTING-but-unreadable local root must NOT
      # nil the whole bundle (that would drop clientAuth → fail-open the mTLS
      # gate). It degrades to the readable source (agent chain) with clientAuth
      # still emitted.
      it "degrades to the agent chain (clientAuth preserved) when the local root is unreadable" do
        _agent_key, agent_ca = build_ca_cert("Agent Enrollment CA (test)")
        _local_key, local_ca = build_ca_cert("Local Hub Internal CA (test)")
        agent_dir = Dir.mktmpdir("agent-pki")
        local_dir = Dir.mktmpdir("local-ca")
        local_root = File.join(local_dir, "root.crt")
        File.write(File.join(agent_dir, "ca-chain.crt"), agent_ca.to_pem)
        File.write(local_root, local_ca.to_pem)
        ENV["WORKER_PKI_DIR"] = agent_dir
        ENV["POWERNODE_CA_LOCAL_DIR"] = local_dir

        # File.file? is true (it exists) but the read raises — a transient
        # perms/FS glitch on an existing file.
        allow(File).to receive(:read).and_call_original
        allow(File).to receive(:read).with(local_root).and_raise(Errno::EACCES, "permission denied")

        result = described_class.ensure_host_login_ingress!(dynamic_dir: tmp_dynamic_dir, cert_dir: tmp_cert_dir)
        expect(result[:client_auth_ca]).not_to be_nil

        bundle = File.read(result[:client_auth_ca])
        expect(bundle).to include(agent_ca.to_pem.strip)     # readable source kept → gate up
        expect(bundle).not_to include(local_ca.to_pem.strip) # unreadable source skipped

        parsed = YAML.load_file(result[:output_path])
        expect(parsed.dig("tls", "options", "default", "clientAuth", "caFiles"))
          .to eq([ result[:client_auth_ca] ])                # clientAuth STILL emitted
      ensure
        ENV.delete("POWERNODE_CA_LOCAL_DIR")
        FileUtils.rm_rf(agent_dir) if agent_dir
        FileUtils.rm_rf(local_dir) if local_dir
      end
    end
  end
  # ------------------------------------------------------------------
  # Universal strip coverage (imp IMP-79557320ede0)
  # ------------------------------------------------------------------
  #
  # The strip landed on the host-login backend routers only. The per-account
  # BASELINE file (`acme-<id>.yaml`, written by the instance `write!`) routes
  # /api, /agent and /cable to the SAME Rails backend and carried no middlewares
  # at all — and its `Host(...) && PathPrefix(...)` rule is LONGER than the
  # host-login `PathPrefix(...)` rule, so Traefik's rule-length priority makes it
  # WIN. Every host with a per-account file therefore bypassed the host-login
  # strip entirely, and a forged X-Forwarded-Tls-Client-Cert-Info reached
  # Security::MtlsTrust#verify_request's no-PEM branch.
  #
  # These examples enumerate the backend routers OUT OF THE WRITER'S OWN OUTPUT
  # rather than naming them. A router added to BASELINE_ROUTER_SPECS or
  # HOST_LOGIN_BACKEND_PREFIXES tomorrow is covered without editing this spec —
  # a hardcoded list would rot on the next router and silently stop protecting.
  describe "strip coverage over EVERY generated router that reaches the Rails backend" do
    # `def`, not `let`: a memoized helper would render the config ONCE and then
    # hand the same object to every example, which can mask a per-call defect.
    def backend_routers(config)
      config.fetch("http").fetch("routers").select { |_name, r| r["service"] == "powernode-backend" }
    end

    def non_backend_routers(config)
      config.fetch("http").fetch("routers").reject { |_name, r| r["service"] == "powernode-backend" }
    end

    def baseline_config
      result = described_class.new(account: account, dynamic_dir: tmp_dynamic_dir, cert_dir: tmp_cert_dir).write!
      YAML.load_file(result[:output_path])
    end

    # Both mTLS postures of the host-login file, plus the per-account baseline —
    # i.e. every dynamic file core itself emits that defines a backend router.
    def every_generated_config
      configs_that_can_forward_a_cn.merge(
        "host-login (no clientAuth CA)" => described_class.host_login_config("/c/crt", "/c/key")
      )
    end

    # The configs whose routers can actually receive a handshake-verified CN:
    # host-login WITH clientAuth, and the per-account baseline (whose routers
    # carry no tls.options and therefore inherit the `default` store's).
    def configs_that_can_forward_a_cn
      {
        "host-login (clientAuth CA)" => described_class.host_login_config(
          "/c/crt", "/c/key", client_auth_ca: "/certs/internal-ca.crt"
        ),
        "per-account baseline"       => baseline_config
      }
    end

    it "attaches the strip FIRST on every backend router in every generated config" do
      every_generated_config.each do |label, config|
        routers = backend_routers(config)
        expect(routers).not_to be_empty, "#{label}: enumerated no backend routers — the oracle would pass vacuously"

        routers.each do |name, router|
          mw = router["middlewares"]
          expect(mw).to be_present, "#{label}: router #{name} reaches powernode-backend with NO middlewares"
          expect(mw.first).to eq(described_class::STRIP_FORWARDED_CLIENT_CERT_MW),
                              "#{label}: router #{name} does not strip the forwarded-cert header FIRST (got #{mw.inspect})"
        end
      end
    end

    it "defines every middleware it references (each file must stand alone)" do
      # The two files are written in DIFFERENT modes, not side by side: the
      # host-login file's only caller is the system extension's rails-start.sh,
      # and in extension mode the per-account file comes from the extension's
      # writer rather than the baseline. So neither file may lean on the other —
      # a reference to a middleware the file does not define leaves the router in
      # error, which 404s /api rather than merely failing open.
      every_generated_config.each do |label, config|
        referenced = backend_routers(config).values.flat_map { |r| Array(r["middlewares"]) }.uniq
        defined_mw = config.fetch("http").fetch("middlewares", {}).keys
        expect(defined_mw).to include(described_class::STRIP_FORWARDED_CLIENT_CERT_MW),
                              "#{label}: references the strip but does not define it"
        expect(referenced - defined_mw).to be_empty,
                                          "#{label}: references undefined middleware(s) #{(referenced - defined_mw).inspect}"
      end
    end

    it "emits a byte-identical strip definition in every file (no drift between the two writers)" do
      definitions = every_generated_config.values.map do |config|
        config.dig("http", "middlewares", described_class::STRIP_FORWARDED_CLIENT_CERT_MW)
      end
      expect(definitions.uniq.length).to eq(1)
      expect(definitions.first).to eq(
        "headers" => {
          "customRequestHeaders" => {
            Security::MtlsTrust::PEM_HEADER     => "",
            Security::MtlsTrust::SUBJECT_HEADER => ""
          }
        }
      )
    end

    # THE regression oracle for the strip. Traefik PREPENDS an entrypoint's
    # middlewares to each router's own chain (pkg/server/aggregator.go), and
    # write_static_config! puts pass-tls-client-cert@file on `websecure`. So a
    # backend router carrying ONLY the strip runs
    #   pass-tls (sets the CN) → strip (deletes it) → backend sees nothing,
    # and every mTLS worker call loses its identity — a worse outcome than the
    # forgery the strip exists to prevent. A stripping router must therefore
    # re-add the proxy-authentic CN ITSELF, after the strip.
    it "re-adds the verified CN AFTER the strip on every backend router that can receive one" do
      configs_that_can_forward_a_cn.each do |label, config|
        routers = backend_routers(config)
        expect(routers).not_to be_empty, "#{label}: enumerated no backend routers — vacuous"

        routers.each do |name, router|
          expect(router["middlewares"]).to eq(
            [ described_class::STRIP_FORWARDED_CLIENT_CERT_MW, described_class::PASS_TLS_CLIENT_CERT_MW ]
          ), "#{label}: router #{name} strips the CN without re-adding it (got #{router['middlewares'].inspect})"
        end
      end
    end

    it "omits the CN-forwarding middleware only where no client cert can be negotiated" do
      # host-login with NO clientAuth CA: nothing ever negotiates a cert, so
      # there is no CN to preserve — the strip alone is correct there.
      routers = backend_routers(described_class.host_login_config("/c/crt", "/c/key"))
      expect(routers).not_to be_empty
      routers.each_value do |router|
        expect(router["middlewares"]).to eq([ described_class::STRIP_FORWARDED_CLIENT_CERT_MW ])
      end
    end

    it "leaves non-backend routers (frontend catchall, sidekiq) unstripped" do
      every_generated_config.each do |label, config|
        others = non_backend_routers(config)
        expect(others).not_to be_empty, "#{label}: enumerated no non-backend routers — vacuous"

        others.each do |name, router|
          expect(Array(router["middlewares"])).not_to include(described_class::STRIP_FORWARDED_CLIENT_CERT_MW),
                                                      "#{label}: router #{name} does not reach the backend but carries the strip"
        end
      end
    end
  end
end
