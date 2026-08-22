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
  # These exercise the REAL argv builders and guards — no stubbing of the method
  # under test. The jobs' own spec stubs this service wholesale, so without these
  # a wrong flag order or a v6/v7 spelling mistake would reach production green.
  describe 'ImageMagick availability and argv' do
    it 'requires BOTH v6 binaries, not just convert' do
      allow(service).to receive(:on_path?).with('magick').and_return(false)
      allow(service).to receive(:on_path?).with('convert').and_return(true)
      allow(service).to receive(:on_path?).with('identify').and_return(false)

      expect(service.imagemagick_available?).to be false
    end

    it 'is available on a v7-only box with no convert/identify shims' do
      allow(service).to receive(:on_path?).with('magick').and_return(true)

      expect(service.imagemagick_available?).to be true
      expect(service.imagemagick_argv('identify')).to eq(%w[magick identify])
      expect(service.imagemagick_argv('convert')).to eq(%w[magick convert])
    end

    it 'uses the bare v6 spelling when magick is absent' do
      allow(service).to receive(:on_path?).with('magick').and_return(false)

      expect(service.imagemagick_argv('identify')).to eq(%w[identify])
    end

    it 'memoizes each PATH lookup' do
      expect(service).to receive(:system).with('which ffmpeg > /dev/null 2>&1').once.and_return(true)

      3.times { service.ffmpeg_available? }
    end
  end

  describe 'guards fire before any shell-out' do
    it 'identify_image raises rather than execing a missing ImageMagick' do
      allow(service).to receive(:imagemagick_available?).and_return(false)
      expect(service).not_to receive(:system)

      expect { service.identify_image('/nope.jpg') }
        .to raise_error(FileProcessingService::ProcessingError, /ImageMagick is not available/)
    end

    it 'generate_thumbnail raises on a missing ImageMagick' do
      allow(service).to receive(:imagemagick_available?).and_return(false)

      expect { service.generate_thumbnail('/a.jpg', '/b.jpg', 'small') }
        .to raise_error(FileProcessingService::ProcessingError, /ImageMagick is not available/)
    end

    it 'generate_thumbnail rejects an unknown size name' do
      allow(service).to receive(:imagemagick_available?).and_return(true)

      expect { service.generate_thumbnail('/a.jpg', '/b.jpg', 'enormous') }
        .to raise_error(FileProcessingService::ProcessingError, /unknown thumbnail size/)
    end

    it 'generate_thumbnail accepts an explicit geometry string' do
      allow(service).to receive(:imagemagick_available?).and_return(true)
      allow(service).to receive(:imagemagick_argv).and_return(['convert'])
      captured = nil
      allow(Open3).to receive(:capture3) { |*argv| captured = argv; ['', '', instance_double(Process::Status, success?: true)] }

      service.generate_thumbnail('/a.jpg', '/b.jpg', '64x64')

      expect(captured).to include('64x64')
      # -auto-orient must precede -thumbnail or EXIF-rotated photos come out sideways.
      expect(captured.index('-auto-orient')).to be < captured.index('-thumbnail')
      expect(captured.first).to eq('convert')
      expect(captured.last).to eq('/b.jpg')
      # first frame only, or a multi-page TIFF/animated GIF explodes into N outputs
      expect(captured).to include('/a.jpg[0]')
    end

    it 'extract_video_frame raises on a missing ffmpeg' do
      allow(service).to receive(:ffmpeg_available?).and_return(false)

      expect { service.extract_video_frame('/a.mp4', '/b.jpg') }
        .to raise_error(FileProcessingService::ProcessingError, /ffmpeg is not available/)
    end

    it 'extract_video_frame seeks before the input and takes exactly one frame' do
      allow(service).to receive(:ffmpeg_available?).and_return(true)
      captured = nil
      allow(Open3).to receive(:capture3) { |*argv| captured = argv; ['', '', instance_double(Process::Status, success?: true)] }

      service.extract_video_frame('/a.mp4', '/b.jpg', offset_seconds: 7)

      expect(captured.index('-ss')).to be < captured.index('-i')
      expect(captured[captured.index('-ss') + 1]).to eq('7')
      expect(captured[captured.index('-frames:v') + 1]).to eq('1')
    end
  end

  describe 'THUMBNAIL_GEOMETRY' do
    it 'never upscales (every geometry is >-suffixed)' do
      expect(described_class::THUMBNAIL_GEOMETRY.values).to all(end_with('>'))
    end

    it 'covers exactly the sizes the server asks for on image upload' do
      expect(described_class::THUMBNAIL_GEOMETRY.keys).to match_array(%w[small medium large])
    end
  end

end
