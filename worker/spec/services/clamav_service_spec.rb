# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ClamavService do
  let(:valid_env) do
    {
      'CLAMAV_CONNECTION_TYPE' => 'unix',
      'CLAMAV_SOCKET_PATH' => '/var/run/clamav/clamd.ctl'
    }
  end

  let(:mock_socket) { instance_double(UNIXSocket) }

  before do
    mock_powernode_worker_config
    valid_env.each { |key, value| allow(ENV).to receive(:fetch).with(key, anything).and_return(value) }
    allow(ENV).to receive(:fetch).and_call_original
  end

  describe '#initialize' do
    context 'with valid configuration' do
      it 'creates service instance without errors' do
        expect { described_class.new }.not_to raise_error
      end
    end

    context 'with invalid connection type' do
      it 'raises ConfigurationError' do
        allow(ENV).to receive(:fetch).with('CLAMAV_CONNECTION_TYPE', 'unix').and_return('invalid')
        expect { described_class.new }.to raise_error(ClamavService::ConfigurationError, /Invalid CLAMAV_CONNECTION_TYPE/)
      end
    end
  end

  describe '#ping' do
    let(:service) { described_class.new }

    before do
      allow(UNIXSocket).to receive(:new).and_return(mock_socket)
      allow(mock_socket).to receive(:write)
      allow(mock_socket).to receive(:close)
    end

    it 'returns true when daemon responds with PONG' do
      allow(mock_socket).to receive(:read).and_return("PONG\n")

      expect(service.ping).to be true
    end

    it 'returns false when daemon does not respond correctly' do
      allow(mock_socket).to receive(:read).and_return("ERROR\n")

      expect(service.ping).to be false
    end
  end

  describe '#available?' do
    let(:service) { described_class.new }

    it 'returns true when ping succeeds' do
      allow(service).to receive(:ping).and_return(true)
      expect(service.available?).to be true
    end

    it 'returns false when ping fails' do
      allow(service).to receive(:ping).and_raise(StandardError)
      expect(service.available?).to be false
    end
  end

  describe '#scan_file' do
    let(:service) { described_class.new }
    let(:test_file) { '/tmp/test_file.txt' }

    before do
      allow(UNIXSocket).to receive(:new).and_return(mock_socket)
      allow(mock_socket).to receive(:write)
      allow(mock_socket).to receive(:close)
      allow(File).to receive(:exist?).with(test_file).and_return(true)
      allow(File).to receive(:readable?).with(test_file).and_return(true)
      allow(File).to receive(:size).with(test_file).and_return(1024)
    end

    context 'with clean file' do
      it 'returns clean result' do
        allow(mock_socket).to receive(:read).and_return("#{test_file}: OK\n")

        result = service.scan_file(test_file)

        expect(result[:clean]).to be true
        expect(result[:virus_name]).to be_nil
      end
    end

    context 'with infected file' do
      it 'returns infected result with virus name' do
        allow(mock_socket).to receive(:read).and_return("#{test_file}: Eicar-Signature FOUND\n")

        result = service.scan_file(test_file)

        expect(result[:clean]).to be false
        expect(result[:virus_name]).to eq('Eicar-Signature')
      end
    end

    context 'with scan error' do
      it 'raises ScanError' do
        allow(mock_socket).to receive(:read).and_return("#{test_file}: Lstat() ERROR\n")

        expect { service.scan_file(test_file) }.to raise_error(ClamavService::ScanError)
      end
    end

    context 'with non-existent file' do
      it 'raises ScanError' do
        allow(File).to receive(:exist?).with(test_file).and_return(false)

        expect { service.scan_file(test_file) }.to raise_error(ClamavService::ScanError, /not found/)
      end
    end

    context 'with file too large' do
      it 'raises ScanError' do
        allow(File).to receive(:size).with(test_file).and_return(200 * 1024 * 1024)

        expect { service.scan_file(test_file) }.to raise_error(ClamavService::ScanError, /too large/)
      end
    end
  end

  describe '#scan_stream' do
    let(:service) { described_class.new }
    let(:content) { 'test file content' }
    let(:io) { StringIO.new(content) }

    before do
      allow(UNIXSocket).to receive(:new).and_return(mock_socket)
      allow(mock_socket).to receive(:write)
      allow(mock_socket).to receive(:close)
    end

    context 'with clean content' do
      it 'returns clean result' do
        allow(mock_socket).to receive(:gets).and_return("stream: OK\n")

        result = service.scan_stream(io, filename: 'test.txt')

        expect(result[:clean]).to be true
      end
    end

    context 'with infected content' do
      it 'returns infected result' do
        allow(mock_socket).to receive(:gets).and_return("stream: Malware.Test FOUND\n")

        result = service.scan_stream(io, filename: 'test.txt')

        expect(result[:clean]).to be false
        expect(result[:virus_name]).to eq('Malware.Test')
      end
    end
  end

  describe '#version' do
    let(:service) { described_class.new }

    before do
      allow(UNIXSocket).to receive(:new).and_return(mock_socket)
      allow(mock_socket).to receive(:write)
      allow(mock_socket).to receive(:close)
    end

    it 'parses version information' do
      allow(mock_socket).to receive(:read)
        .and_return("ClamAV 0.103.6/26423/Wed Feb 28 08:00:29 2024\n")

      result = service.version

      expect(result[:version]).to eq('ClamAV 0.103.6')
      expect(result[:database_version]).to eq(26423)
    end
  end

  describe 'TCP connection' do
    let(:tcp_env) do
      {
        'CLAMAV_CONNECTION_TYPE' => 'tcp',
        'CLAMAV_TCP_HOST' => 'localhost',
        'CLAMAV_TCP_PORT' => '3310'
      }
    end

    before do
      tcp_env.each { |key, value| allow(ENV).to receive(:fetch).with(key, anything).and_return(value) }
    end

    it 'connects via TCP socket' do
      mock_tcp = instance_double(TCPSocket)
      allow(TCPSocket).to receive(:new).with('localhost', 3310).and_return(mock_tcp)
      allow(mock_tcp).to receive(:write)
      allow(mock_tcp).to receive(:read).and_return("PONG\n")
      allow(mock_tcp).to receive(:close)

      service = described_class.new
      expect(service.ping).to be true
    end
  end
end
