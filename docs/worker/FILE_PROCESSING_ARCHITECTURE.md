# File Processing Architecture

## Overview

The Powernode file processing system provides automated processing of uploaded files through a dedicated Sidekiq worker service. This document describes the architecture, job types, and integration patterns for the file processing subsystem.

## Architecture Principles

### Worker Service Isolation
- **Complete Separation**: File processing runs in a standalone Sidekiq service (`worker/`) separate from the main Rails application (`server/`)
- **API-Only Communication**: Workers communicate with the backend exclusively through HTTP API calls - no direct database access
- **Service Token Authentication**: Workers authenticate using `WORKER_SERVICE_TOKEN` environment variable
- **Process Isolation**: Crashes or resource exhaustion in file processing don't affect the main application

### Base Class Hierarchy
```
BaseJob (worker/app/jobs/base_job.rb)
  └── FileProcessingWorker (worker/app/jobs/file_processing_worker.rb)
        ├── ThumbnailGenerationJob
        ├── MetadataExtractionJob
        ├── VideoProcessingJob
        └── AudioProcessingJob
```

### Queue Configuration
- **Queue Name**: `file_processing`
- **Priority**: 2 (medium priority)
- **Retry Policy**: 3 attempts with exponential backoff
- **Timeout**: 300 seconds (5 minutes) per job
- **Dead Job Queue**: Enabled for failed jobs after all retries

## Job Types

### 1. ThumbnailGenerationJob
**Purpose**: Generate multiple thumbnail sizes for image files

**Functionality**:
- Downloads original image from backend
- Generates three thumbnail sizes:
  - **Small**: 150x150px (for lists, grids)
  - **Medium**: 300x300px (for previews)
  - **Large**: 600x600px (for detailed views)
- Maintains aspect ratio with letterboxing
- Compresses to JPEG format at 85% quality
- Uploads thumbnails back to backend storage

**Dependencies**:
- `mini_magick` gem (ImageMagick wrapper)
- ImageMagick system binary (`convert` command)

**Triggered By**:
- Image file uploads (JPEG, PNG, GIF, WebP, BMP, TIFF)

### 2. MetadataExtractionJob
**Purpose**: Extract metadata from documents and images

**Functionality**:
- **Image Metadata**:
  - Dimensions (width, height)
  - EXIF data (camera make/model, GPS, timestamp, settings)
  - Color profile information
- **Document Metadata**:
  - Page count
  - Author and creation date
  - Document properties
  - Text extraction (future enhancement)
- Updates FileObject metadata field via backend API

**Dependencies**:
- `mini_exiftool` gem
- `exiftool` system binary (minimum version 7.65)

**Triggered By**:
- All file types (images, documents, PDFs, etc.)

### 3. VideoProcessingJob
**Purpose**: Process video files and extract metadata

**Functionality**:
- Extracts video metadata:
  - Duration, dimensions, bitrate
  - Video codec and audio codec
  - Frame rate
- Generates poster frame (thumbnail from first frame)
- Future enhancements:
  - Multiple poster frames
  - Video transcoding for web playback
  - Subtitle extraction

**Dependencies**:
- `streamio-ffmpeg` gem
- FFmpeg and FFprobe system binaries

**Triggered By**:
- Video file uploads (MP4, AVI, MOV, MKV, WebM, FLV, WMV, M4V)

### 4. AudioProcessingJob
**Purpose**: Process audio files and extract metadata

**Functionality**:
- Extracts audio metadata:
  - Duration, bitrate, sample rate
  - Audio codec information
  - Channels (mono, stereo, surround)
- Future enhancements:
  - Waveform generation
  - Audio transcoding
  - ID3 tag extraction

**Dependencies**:
- `streamio-ffmpeg` gem
- FFmpeg and FFprobe system binaries

**Triggered By**:
- Audio file uploads (MP3, WAV, FLAC, AAC, OGG, M4A, WMA)

## FileProcessingWorker Base Class

### Common Methods

#### File Operations
```ruby
# Download file from backend to temporary file
download_file_content(file_object_id)
  → returns Tempfile with binary content

# Upload processed file result
upload_processed_file(file_object_id, file_path, metadata = {})
  → uploads via Base64 encoding

# Update file metadata
update_file_metadata(file_object_id, metadata_updates)

# Update file processing status
update_file_processing_status(file_object_id, status)
```

#### Job Status Management
```ruby
# Load job and file data
load_processing_job(processing_job_id)
load_file_object(file_object_id)

# Update job status
start_processing_job!(processing_job_id)
complete_processing_job!(processing_job_id, result_data = {})
fail_processing_job!(processing_job_id, error_message, error_data = {})
```

#### Utility Helpers
```ruby
# Create working directory for processing
with_working_directory { |dir| ... }

# Cleanup temporary files
cleanup_temp_file(temp_file)

# Access file processing service
processing_service
```

## API Integration

### Backend API Client

**File Operations** (`BackendApiClient`):
```ruby
# Download file content
download_file_content(file_id)
  → GET /api/v1/worker/files/:id/download
  → returns binary content

# Upload processed file
upload_processed_file(file_id, file_content, metadata = {})
  → POST /api/v1/worker/files/:id/processed
  → payload: { file_content: Base64.encode(content), metadata: {...} }

# Get file object data
get_file_object(file_id)
  → GET /api/v1/worker/files/:id

# Update file object
update_file_object(file_id, updates)
  → PATCH /api/v1/worker/files/:id
```

**Processing Job Operations**:
```ruby
# Get processing job
get_file_processing_job(job_id)
  → GET /api/v1/worker/processing_jobs/:id

# Update job status
update_file_processing_job(job_id, updates)
  → PATCH /api/v1/worker/processing_jobs/:id

# Mark job completed
complete_file_processing_job(job_id, result_data)
  → PATCH /api/v1/worker/processing_jobs/:id
  → payload: { status: 'completed', result_data: {...} }

# Mark job failed
fail_file_processing_job(job_id, error_message, error_data)
  → PATCH /api/v1/worker/processing_jobs/:id
  → payload: { status: 'failed', error_details: {...} }
```

### Authentication
All worker API requests include service token authentication:
```ruby
headers['Authorization'] = "Bearer #{ENV['WORKER_SERVICE_TOKEN']}"
```

Backend validates token in `WorkerBaseController`:
```ruby
def authenticate_worker_service!
  token = request.headers['Authorization']&.remove('Bearer ')
  unless valid_worker_token?(token)
    render_error('Service authentication required', status: :unauthorized)
  end
end
```

## Processing Workflow

### 1. File Upload Trigger
```ruby
# FileStorageService (server/app/services/file_storage_service.rb)
def upload_file(uploaded_file, filename:, **options)
  # 1. Create FileObject record with processing_status: 'pending'
  file_object = FileObject.create!(
    filename: filename,
    processing_status: 'pending',
    ...
  )

  # 2. Upload to storage provider
  provider.upload_file(file_object, uploaded_file, options)

  # 3. Queue processing jobs based on file type
  queue_processing_jobs(file_object, options[:processing_tasks] || [])
end
```

### 2. Job Queueing
```ruby
# FileObject model (server/app/models/file_object.rb)
def queue_processing_jobs
  if image?
    queue_processing_job('thumbnail', { sizes: ['small', 'medium', 'large'] })
    queue_processing_job('metadata_extract')
  elsif document?
    queue_processing_job('metadata_extract')
  elsif video?
    queue_processing_job('video_processing')
  elsif audio?
    queue_processing_job('audio_processing')
  end
end

# FileStorageService dispatches Sidekiq jobs
def queue_processing_job(file_object, job_type, configuration = {})
  job = FileProcessingJob.create!(
    file_object: file_object,
    job_type: job_type,
    configuration: configuration,
    status: 'pending'
  )

  case job_type
  when 'thumbnail'
    ThumbnailGenerationJob.perform_async(job.id)
  when 'metadata_extract'
    MetadataExtractionJob.perform_async(job.id)
  when 'video_processing'
    VideoProcessingJob.perform_async(job.id)
  when 'audio_processing'
    AudioProcessingJob.perform_async(job.id)
  end
end
```

### 3. Worker Job Execution
```ruby
# Example: ThumbnailGenerationJob
class ThumbnailGenerationJob < FileProcessingWorker
  def execute(processing_job_id)
    # 1. Load job and file data from backend API
    job_data = load_processing_job(processing_job_id)
    file_data = load_file_object(job_data['file_object_id'])

    # 2. Mark job as processing
    start_processing_job!(processing_job_id)

    # 3. Download file content
    temp_file = download_file_content(file_data['id'])

    # 4. Process file (generate thumbnails)
    with_working_directory do |dir|
      thumbnails = generate_thumbnails(temp_file.path, ['small', 'medium', 'large'])

      # 5. Upload processed files back to backend
      thumbnails.each do |size, thumbnail_path|
        upload_processed_file(file_data['id'], thumbnail_path, {
          thumbnail_size: size,
          thumbnail_dimensions: get_dimensions(thumbnail_path)
        })
      end
    end

    # 6. Update file metadata
    update_file_metadata(file_data['id'], {
      thumbnails_generated: true,
      thumbnail_sizes: ['small', 'medium', 'large']
    })

    # 7. Mark job as completed
    complete_processing_job!(processing_job_id, {
      thumbnails_count: 3,
      completed_at: Time.current
    })

    # 8. Update file processing status
    update_file_processing_status(file_data['id'], 'completed')

  rescue StandardError => e
    # Handle errors and mark job as failed
    fail_processing_job!(processing_job_id, e.message, {
      error_class: e.class.name,
      backtrace: e.backtrace.first(5)
    })
    raise
  ensure
    cleanup_temp_file(temp_file)
  end
end
```

## Configuration

### Environment Variables
```bash
# Worker Service Configuration
WORKER_SERVICE_TOKEN=<secure-random-token>  # Authentication token for worker-to-backend API calls
BACKEND_API_URL=http://localhost:3000       # Backend API endpoint
REDIS_URL=redis://localhost:6379/1          # Redis connection for Sidekiq

# File Processing Paths
IMAGEMAGICK_PATH=/usr/bin/convert           # Optional: Explicit ImageMagick path
FFMPEG_PATH=/usr/bin/ffmpeg                 # Optional: Explicit FFmpeg path
EXIFTOOL_PATH=/usr/bin/exiftool             # Optional: Explicit ExifTool path
```

### Sidekiq Queue Configuration
```yaml
# worker/config/sidekiq.yml
:queues:
  - [critical, 3]           # Highest priority
  - [high, 3]
  - [file_processing, 2]    # Medium priority for file processing
  - [billing, 2]
  - [email, 2]
  - [default, 1]            # Lowest priority
```

### System Dependencies

**Required System Binaries**:
```bash
# ImageMagick (for ThumbnailGenerationJob)
sudo apt-get install imagemagick
convert -version  # Verify installation

# ExifTool (for MetadataExtractionJob)
sudo apt-get install libimage-exiftool-perl
exiftool -ver  # Should be >= 7.65

# FFmpeg (for VideoProcessingJob and AudioProcessingJob)
sudo apt-get install ffmpeg
ffmpeg -version
ffprobe -version
```

**Ruby Gems** (`worker/Gemfile`):
```ruby
gem 'mini_magick', '~> 4.12'        # ImageMagick wrapper
gem 'mini_exiftool', '~> 2.11'     # EXIF data extraction
gem 'streamio-ffmpeg', '~> 3.0'    # Video/audio processing
```

## Error Handling

### Retry Strategy
- **Automatic Retries**: 3 attempts with exponential backoff (BaseJob configuration)
- **Backoff Schedule**:
  - 1st retry: immediate
  - 2nd retry: 15 seconds
  - 3rd retry: 60 seconds
- **Dead Job Queue**: After all retries exhausted, jobs move to dead queue for manual review

### Error Scenarios

**1. File Download Failure**
```ruby
# BackendApiClient raises ApiError
rescue BackendApiClient::ApiError => e
  fail_processing_job!(processing_job_id, "Failed to download file", {
    error_type: 'download_failure',
    api_error: e.message
  })
end
```

**2. Processing Failure**
```ruby
# ImageMagick/FFmpeg errors
rescue MiniMagick::Error => e
  fail_processing_job!(processing_job_id, "Image processing failed", {
    error_type: 'imagemagick_error',
    details: e.message
  })
end
```

**3. Upload Failure**
```ruby
# Failed to upload processed file
rescue BackendApiClient::ApiError => e
  fail_processing_job!(processing_job_id, "Failed to upload result", {
    error_type: 'upload_failure',
    api_error: e.message
  })
end
```

### Status Tracking
FileObject and FileProcessingJob maintain comprehensive status tracking:

**FileObject.processing_status**:
- `pending` - Awaiting processing
- `processing` - Currently being processed
- `completed` - All processing jobs completed
- `failed` - Processing failed after retries

**FileProcessingJob.status**:
- `pending` - Queued but not started
- `processing` - Currently executing
- `completed` - Successfully completed
- `failed` - Failed after retries

## Monitoring and Debugging

### Sidekiq Web UI
Access the Sidekiq web interface to monitor jobs:
```
http://localhost:4567/sidekiq
```

**Available Information**:
- Queue depths and processing rates
- Failed jobs with error details
- Retry queue status
- Dead job queue for manual review
- Real-time job execution

### Worker Logs
```bash
# Follow worker logs
tail -f logs/worker.log

# Search for specific job type
grep "ThumbnailGenerationJob" logs/worker.log

# Find failed jobs
grep "ERROR" logs/worker.log | grep "file_processing"
```

### Backend Logs
```bash
# Follow backend logs
cd server && tail -f log/development.log

# Search for worker API calls
grep "WorkerFilesController" server/log/development.log
grep "ProcessingJobsController" server/log/development.log
```

### Health Checks
```bash
# Check worker status
systemctl status powernode-worker@default

# Verify queue is processing
redis-cli -n 1
> LLEN queue:file_processing
> SCARD queues

# Check for stuck jobs
# Jobs processing for > 5 minutes may be stuck
```

## Testing

### Manual Testing Workflow
1. Upload a test file through the application
2. Monitor Sidekiq web UI for job execution
3. Check FileObject record for updated metadata
4. Verify processed files (thumbnails) in storage
5. Check FileProcessingJob records for status

### RSpec Testing
```ruby
# spec/jobs/thumbnail_generation_job_spec.rb
RSpec.describe ThumbnailGenerationJob do
  let(:job) { described_class.new }
  let(:processing_job_id) { 'test-job-id' }

  before do
    # Stub BackendApiClient responses
    allow(job).to receive(:load_processing_job).and_return(job_data)
    allow(job).to receive(:download_file_content).and_return(temp_file)
  end

  it 'generates thumbnails successfully' do
    job.execute(processing_job_id)

    expect(job).to have_received(:complete_processing_job!)
    expect(job).to have_received(:upload_processed_file).exactly(3).times
  end
end
```

### Integration Testing
```ruby
# Test full workflow from file upload to completion
RSpec.describe 'File Processing Integration' do
  it 'processes uploaded image file end-to-end' do
    # 1. Upload file
    file = fixture_file_upload('test_image.jpg', 'image/jpeg')
    post api_v1_files_path, params: { file: file }

    # 2. Wait for Sidekiq job processing
    perform_enqueued_jobs

    # 3. Verify results
    file_object = FileObject.last
    expect(file_object.processing_status).to eq('completed')
    expect(file_object.metadata['thumbnails_generated']).to be true
  end
end
```

## Performance Considerations

### Resource Limits
- **Memory**: Each file processing job can consume 100-500MB depending on file size
- **Concurrency**: Sidekiq concurrency set to 5 workers (configurable in sidekiq.yml)
- **Disk Space**: Temporary files cleaned up after processing, but monitor `/tmp` usage

### Optimization Strategies
1. **Thumbnail Caching**: Generated thumbnails stored in backend, not regenerated
2. **Lazy Processing**: Only generate thumbnails/metadata when requested (future enhancement)
3. **Batch Processing**: Process multiple files in single job (future enhancement)
4. **Progressive Processing**: Start with small thumbnails, queue larger sizes separately

## Future Enhancements

### Planned Features
1. **OCR Processing**: Extract text from images and PDFs
2. **Virus Scanning**: Integrate ClamAV for malware detection
3. **Video Transcoding**: Convert videos to web-friendly formats
4. **Batch Operations**: Process multiple files in single job
5. **Priority Queue**: Expedite processing for premium users
6. **Webhook Notifications**: Notify clients when processing completes
7. **Progress Tracking**: Real-time progress updates via WebSocket
8. **Custom Processing Pipelines**: User-defined processing workflows

### Scalability Plans
1. **Horizontal Scaling**: Add more worker instances as load increases
2. **Queue Partitioning**: Separate queues per file type for better isolation
3. **Cloud Processing**: Offload heavy processing to AWS Lambda or similar
4. **CDN Integration**: Automatically upload processed files to CDN
5. **Distributed Storage**: Support S3, GCS, Azure Blob for file storage

## Troubleshooting

### Common Issues

**Issue**: Jobs stuck in "processing" status
- **Cause**: Worker crashed or timeout exceeded
- **Solution**: Check worker logs, restart worker service, manually fail stuck jobs

**Issue**: "mini_magick not found" error
- **Cause**: ImageMagick not installed or not in PATH
- **Solution**: Install ImageMagick system binary, verify with `which convert`

**Issue**: "exiftool not found" error
- **Cause**: ExifTool not installed
- **Solution**: Install libimage-exiftool-perl package

**Issue**: FFmpeg processing fails
- **Cause**: Unsupported video codec or corrupted file
- **Solution**: Check FFmpeg logs, verify file integrity, add codec support

**Issue**: Worker authentication fails
- **Cause**: WORKER_SERVICE_TOKEN mismatch or missing
- **Solution**: Verify environment variables match in worker and backend

### Debug Checklist
1. ✓ Worker service running? (`systemctl status powernode-worker@default`)
2. ✓ Backend API accessible? (`curl http://localhost:3000/health`)
3. ✓ Redis connection working? (`redis-cli -n 1 ping`)
4. ✓ System binaries installed? (`which convert exiftool ffmpeg`)
5. ✓ Service token configured? (`echo $WORKER_SERVICE_TOKEN`)
6. ✓ Sidekiq queue processing? (Check web UI at :4567/sidekiq)
7. ✓ Disk space available? (`df -h /tmp`)

## Related Documentation
- [Background Job Engineer Specialist](../backend/BACKGROUND_JOB_ENGINEER_SPECIALIST.md) - Worker job patterns
- [Rails Architect Specialist](../backend/RAILS_ARCHITECT_SPECIALIST.md) - Backend API patterns

## Summary

The Powernode file processing system provides robust, scalable file processing through:
- ✅ **Isolated Worker Service**: File processing isolated from main application
- ✅ **API-First Communication**: No direct database access, all via HTTP API
- ✅ **Type-Specific Processing**: Dedicated jobs for images, videos, audio, documents
- ✅ **Comprehensive Error Handling**: Retry logic, failure tracking, dead job queue
- ✅ **Monitoring and Debugging**: Sidekiq web UI, detailed logging, health checks
- ✅ **Extensible Architecture**: Easy to add new processing job types

The system is production-ready and provides a solid foundation for future file processing enhancements.
