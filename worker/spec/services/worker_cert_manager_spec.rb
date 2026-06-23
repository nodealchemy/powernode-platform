# frozen_string_literal: true

require 'spec_helper'
require 'openssl'
require 'tmpdir'
require 'fileutils'
require_relative '../../app/services/worker_cert_manager'

RSpec.describe WorkerCertManager do
  let(:dir) { Dir.mktmpdir }

  after do
    FileUtils.remove_entry(dir) if Dir.exist?(dir)
    described_class.reset!
  end

  def write_cert(target, cn: 'node-123', not_after: Time.now + 3600)
    key = OpenSSL::PKey::RSA.new(2048)
    cert = OpenSSL::X509::Certificate.new
    cert.version = 2
    cert.serial = 1
    name = OpenSSL::X509::Name.new([['CN', cn]])
    cert.subject = name
    cert.issuer = name
    cert.public_key = key.public_key
    cert.not_before = Time.now - 60
    cert.not_after = not_after
    cert.sign(key, OpenSSL::Digest.new('SHA256'))
    File.write(File.join(target, 'node.crt'), cert.to_pem)
    File.write(File.join(target, 'node.key'), key.to_pem)
    cert
  end

  describe '#initialize path derivation' do
    it 'derives node.crt/node.key/ca-bundle.crt under the dir' do
      mgr = described_class.new(dir: '/x/pki')
      expect(mgr.cert_path).to eq('/x/pki/node.crt')
      expect(mgr.key_path).to eq('/x/pki/node.key')
      expect(mgr.ca_path).to eq('/x/pki/ca-bundle.crt')
    end
  end

  describe '#ssl_options' do
    it 'assembles client_cert/client_key/verify from on-disk material' do
      cert = write_cert(dir)
      opts = described_class.new(dir: dir).ssl_options

      expect(opts[:client_cert]).to be_a(OpenSSL::X509::Certificate)
      expect(opts[:client_cert].to_pem).to eq(cert.to_pem)
      expect(opts[:client_key]).to be_a(OpenSSL::PKey::RSA)
      expect(opts[:verify]).to be(true)
    end

    it 'honors WORKER_TLS_VERIFY=false' do
      write_cert(dir)
      original = ENV['WORKER_TLS_VERIFY']
      ENV['WORKER_TLS_VERIFY'] = 'false'
      begin
        expect(described_class.new(dir: dir).ssl_options[:verify]).to be(false)
      ensure
        original.nil? ? ENV.delete('WORKER_TLS_VERIFY') : ENV['WORKER_TLS_VERIFY'] = original
      end
    end

    it 'returns a pass-through { verify: false } in test env when no cert is on disk' do
      # dir is empty (no node.crt); RAILS_ENV=test
      expect(described_class.new(dir: dir).ssl_options).to eq({ verify: false })
    end
  end

  describe '#common_name / #not_after' do
    it 'reads the CN from the leaf cert subject' do
      write_cert(dir, cn: 'node-abc-123')
      expect(described_class.new(dir: dir).common_name).to eq('node-abc-123')
    end

    it 'exposes the cert NotAfter (to whole-second precision)' do
      exp = Time.now + 7200
      write_cert(dir, not_after: exp)
      expect(described_class.new(dir: dir).not_after.to_i).to eq(exp.to_i)
    end
  end

  describe '.instance / .reset!' do
    it 'memoizes the singleton and reset! clears it' do
      a = described_class.instance
      expect(described_class.instance).to be(a)
      described_class.reset!
      expect(described_class.instance).not_to be(a)
    end
  end
end
