# frozen_string_literal: true

require "rails_helper"

RSpec.describe Setup::DomainConfigurator do
  def trusted_hosts = AdminSetting.reverse_proxy_url_config[:trusted_hosts]
  def cors_origins = CorsConfigurationService.send(:parse_cors_origins, AdminSetting.get("cors_allowed_origins", []))

  # The same lambda development.rb registers, wrapped in the real middleware.
  def host_status(host)
    inner = ->(_env) { [ 200, {}, [ "ok" ] ] }
    app = ActionDispatch::HostAuthorization.new(inner, [ ->(h) { TrustedHostPolicy.allowed?(h) } ])
    Rack::MockRequest.new(app).get("/", "HTTP_HOST" => host).status
  end

  describe ".call" do
    it "authorizes every domain through HostAuthorization and adds their CORS origins" do
      described_class.call(primary: "fleet.example.com", additional: [ "ops.example.org", "*.apps.example.org" ])

      expect(host_status("fleet.example.com")).to eq(200)
      expect(host_status("ops.example.org:3000")).to eq(200)
      expect(host_status("x.apps.example.org")).to eq(200)
      expect(host_status("evil.example.net")).to eq(403)
      expect(cors_origins).to include("https://fleet.example.com", "https://ops.example.org")
      expect(cors_origins.grep(/\*/)).to be_empty
    end

    it "keeps the primary feeding SiteSetting domain" do
      described_class.call(primary: "fleet.example.com", additional: [ "ops.example.org" ])
      expect(SiteSetting.get("domain")).to eq("fleet.example.com")
    end

    it "rejects an invalid hostname and writes nothing" do
      expect { described_class.call(primary: "fleet.example.com", additional: [ "bad host!" ]) }
        .to raise_error(Setup::DomainConfigurator::InvalidDomain)
      expect(SiteSetting.get("domain")).to be_nil
      expect(trusted_hosts).not_to include("fleet.example.com")
    end

    it "rejects overly broad wildcards (single label, public suffix, numeric TLD)" do
      [ "*.com", "*.1", "*.co.uk", "*.localhost", "*.com:3000" ].each do |bad|
        expect { described_class.call(primary: "fleet.example.com", additional: [ bad ]) }
          .to raise_error(Setup::DomainConfigurator::InvalidDomain), "expected #{bad} to be rejected"
      end
    end

    it "wildcards match subdomains but not look-alike suffixes" do
      described_class.call(primary: "fleet.example.com", additional: [ "*.example.org" ])
      expect(host_status("sub.example.org")).to eq(200)
      expect(host_status("example.org")).to eq(200)
      expect(host_status("evilexample.org")).to eq(403)
      origin_regex = CorsConfigurationService.allowed_origins.find { |o| o.start_with?("/") }
      expect(origin_regex).to be_present
      re = Regexp.new(origin_regex[1..-2])
      expect(re.match?("https://sub.example.org")).to be(true)
      expect(re.match?("https://evilexample.org")).to be(false)
    end

    it "rejects localhost and 127.0.0.1 as wizard domains" do
      [ "localhost", "127.0.0.1" ].each do |bad|
        expect { described_class.call(primary: "fleet.example.com", additional: [ bad ]) }
          .to raise_error(Setup::DomainConfigurator::InvalidDomain)
      end
    end

    it "rejects a scheme, path or wildcard primary" do
      [ "https://a.example.com", "a.example.com/x", "*.example.com", "" ].each do |bad|
        expect { described_class.call(primary: bad) }.to raise_error(Setup::DomainConfigurator::InvalidDomain)
      end
    end

    it "is idempotent" do
      2.times { described_class.call(primary: "fleet.example.com", additional: [ "ops.example.org" ]) }

      expect(trusted_hosts.count("fleet.example.com")).to eq(1)
      expect(trusted_hosts.count("ops.example.org")).to eq(1)
      expect(cors_origins.count("https://fleet.example.com")).to eq(1)
    end

    it "preserves operator CORS entries and operator trusted hosts" do
      AdminSetting.set("cors_allowed_origins", [ "https://operator.example.com" ])
      AdminSetting.add_trusted_host("operator.example.com")

      described_class.call(primary: "fleet.example.com")

      expect(cors_origins).to include("https://operator.example.com", "https://fleet.example.com")
      expect(trusted_hosts).to include("operator.example.com", "fleet.example.com", "localhost")
    end

    it "drops previously wizard-managed domains that were removed on a re-run" do
      described_class.call(primary: "a.example.com", additional: [ "b.example.com" ])
      described_class.call(primary: "a.example.com")

      expect(trusted_hosts).to include("a.example.com")
      expect(trusted_hosts).not_to include("b.example.com")
      expect(cors_origins).not_to include("https://b.example.com")
    end

    it "never removes an entry the operator added first, even if later entered and removed in the wizard" do
      AdminSetting.add_trusted_host("shared.example.com")
      AdminSetting.set("cors_allowed_origins", [ "https://shared.example.com" ])

      described_class.call(primary: "a.example.com", additional: [ "shared.example.com" ])
      described_class.call(primary: "a.example.com")

      expect(trusted_hosts).to include("shared.example.com", "localhost", "127.0.0.1")
      expect(cors_origins).to include("https://shared.example.com")
    end

    it "removes only entries it added itself" do
      described_class.call(primary: "a.example.com", additional: [ "b.example.com" ])
      described_class.call(primary: "a.example.com")
      expect(trusted_hosts).not_to include("b.example.com")
      expect(trusted_hosts).to include("localhost", "127.0.0.1")
    end

    it "audits the trusted hosts and CORS changes" do
      account = create(:account)
      user = create(:user, account: account)
      expect do
        described_class.call(primary: "a.example.com", additional: [ "b.example.com" ], user: user, account: account, ip_address: "10.0.0.1")
      end.to change { AuditLog.where(action: "admin_settings_update").count }.by(1)

      log = AuditLog.where(action: "admin_settings_update").last
      expect(log.metadata["change"]).to eq("setup.domains_configured")
      expect(log.user).to eq(user)
      expect(log.metadata).to include("domains" => %w[a.example.com b.example.com])
      expect(log.metadata["trusted_hosts_added"]).to include("a.example.com", "b.example.com")
      expect(log.metadata["cors_origins_added"]).to include("https://a.example.com")
    end

    it "adds the dev frontend origin in development" do
      allow(Rails.env).to receive(:development?).and_return(true)
      described_class.call(primary: "fleet.example.com")
      expect(cors_origins).to include("http://fleet.example.com:3001")
    end
  end
end
