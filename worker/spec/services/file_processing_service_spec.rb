# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FileProcessingService do
  subject(:service) { described_class.new }

  before do
    allow(PowernodeWorker).to receive(:application).and_return(
      double('app', logger: Logger.new(File::NULL))
    )
  end

  def status_double(success)
    instance_double(Process::Status, success?: success)
  end

  describe '#stitch_scenes' do
    let(:scenes) { ['/tmp/scene_0000', '/tmp/scene_0001'] }
    let(:output) { '/tmp/stitched.mp4' }

    before { allow(service).to receive(:ffmpeg_available?).and_return(true) }

    it 'runs ffmpeg with the concat demuxer + stream copy and returns the output path' do
      captured = []
      allow(Open3).to receive(:capture3) do |*cmd|
        captured << cmd
        ['', '', status_double(true)]
      end

      expect(service.stitch_scenes(scenes, output)).to eq(output)

      expect(captured.length).to eq(1)
      expect(captured.first).to include('ffmpeg', '-f', 'concat', '-safe', '0', '-c', 'copy', output)
    end

    it 'falls back to a re-encode when stream copy fails' do
      statuses = [status_double(false), status_double(true)]
      captured = []
      allow(Open3).to receive(:capture3) do |*cmd|
        captured << cmd
        ['', 'copy error', statuses.shift]
      end

      expect(service.stitch_scenes(scenes, output)).to eq(output)
      expect(captured.length).to eq(2)
      expect(captured.last).to include('-c:v', 'libx264', '-c:a', 'aac')
    end

    it 'raises when both stream copy and re-encode fail' do
      allow(Open3).to receive(:capture3).and_return(['', 'boom', status_double(false)])
      expect { service.stitch_scenes(scenes, output) }
        .to raise_error(FileProcessingService::ProcessingError, /ffmpeg stitch failed/)
    end

    it 'raises when ffmpeg is unavailable' do
      allow(service).to receive(:ffmpeg_available?).and_return(false)
      expect { service.stitch_scenes(scenes, output) }
        .to raise_error(FileProcessingService::ProcessingError, /ffmpeg is not available/)
    end

    it 'raises when there are no scenes' do
      expect { service.stitch_scenes([], output) }
        .to raise_error(FileProcessingService::ProcessingError, /no scenes/)
    end

    it 'writes one concat line per scene, in order' do
      lines = nil
      allow(Open3).to receive(:capture3) do |*cmd|
        list_path = cmd[cmd.index('-i') + 1]
        lines = File.readlines(list_path).map(&:strip)
        ['', '', status_double(true)]
      end

      service.stitch_scenes(scenes, output)
      expect(lines).to eq(["file '/tmp/scene_0000'", "file '/tmp/scene_0001'"])
    end
  end

  describe '#probe_metadata' do
    before { allow(service).to receive(:ffprobe_available?).and_return(true) }

    it 'returns parsed ffprobe JSON' do
      json = { 'format' => { 'duration' => '12.5' }, 'streams' => [{ 'codec_type' => 'video' }] }.to_json
      allow(Open3).to receive(:capture3).and_return([json, '', status_double(true)])

      result = service.probe_metadata('/tmp/stitched.mp4')
      expect(result.dig('format', 'duration')).to eq('12.5')
    end

    it 'invokes ffprobe with json output flags' do
      captured = nil
      allow(Open3).to receive(:capture3) do |*cmd|
        captured = cmd
        ['{}', '', status_double(true)]
      end

      service.probe_metadata('/tmp/x.mp4')
      expect(captured).to include('ffprobe', '-print_format', 'json', '-show_format', '-show_streams', '/tmp/x.mp4')
    end

    it 'raises when ffprobe is unavailable' do
      allow(service).to receive(:ffprobe_available?).and_return(false)
      expect { service.probe_metadata('/tmp/x.mp4') }
        .to raise_error(FileProcessingService::ProcessingError, /ffprobe is not available/)
    end

    it 'raises when ffprobe fails' do
      allow(Open3).to receive(:capture3).and_return(['', 'bad file', status_double(false)])
      expect { service.probe_metadata('/tmp/x.mp4') }
        .to raise_error(FileProcessingService::ProcessingError, /ffprobe failed/)
    end
  end
end
