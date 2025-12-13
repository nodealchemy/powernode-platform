import React, { useRef, useState, useEffect } from 'react';
import {
  PlayIcon,
  PauseIcon,
  SpeakerWaveIcon,
  SpeakerXMarkIcon,
  BackwardIcon,
  ForwardIcon,
} from '@heroicons/react/24/solid';
import { FileObject } from '@/features/files/services/filesApi';

interface FilePreviewAudioProps {
  file: FileObject;
  previewUrl: string | null;
}

export const FilePreviewAudio: React.FC<FilePreviewAudioProps> = ({
  file,
  previewUrl,
}) => {
  const audioRef = useRef<HTMLAudioElement>(null);
  const [isPlaying, setIsPlaying] = useState(false);
  const [isMuted, setIsMuted] = useState(false);
  const [currentTime, setCurrentTime] = useState(0);
  const [duration, setDuration] = useState(0);
  const [volume, setVolume] = useState(1);
  const [loadError, setLoadError] = useState(false);

  useEffect(() => {
    const audio = audioRef.current;
    if (!audio) return;

    const handleTimeUpdate = () => setCurrentTime(audio.currentTime);
    const handleLoadedMetadata = () => setDuration(audio.duration);
    const handleEnded = () => setIsPlaying(false);
    const handlePlay = () => setIsPlaying(true);
    const handlePause = () => setIsPlaying(false);

    audio.addEventListener('timeupdate', handleTimeUpdate);
    audio.addEventListener('loadedmetadata', handleLoadedMetadata);
    audio.addEventListener('ended', handleEnded);
    audio.addEventListener('play', handlePlay);
    audio.addEventListener('pause', handlePause);

    return () => {
      audio.removeEventListener('timeupdate', handleTimeUpdate);
      audio.removeEventListener('loadedmetadata', handleLoadedMetadata);
      audio.removeEventListener('ended', handleEnded);
      audio.removeEventListener('play', handlePlay);
      audio.removeEventListener('pause', handlePause);
    };
  }, []);

  const togglePlay = () => {
    if (audioRef.current) {
      if (isPlaying) {
        audioRef.current.pause();
      } else {
        audioRef.current.play();
      }
    }
  };

  const toggleMute = () => {
    if (audioRef.current) {
      audioRef.current.muted = !audioRef.current.muted;
      setIsMuted(audioRef.current.muted);
    }
  };

  const handleSeek = (e: React.ChangeEvent<HTMLInputElement>) => {
    const time = parseFloat(e.target.value);
    if (audioRef.current) {
      audioRef.current.currentTime = time;
      setCurrentTime(time);
    }
  };

  const handleVolumeChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const vol = parseFloat(e.target.value);
    if (audioRef.current) {
      audioRef.current.volume = vol;
      setVolume(vol);
      setIsMuted(vol === 0);
    }
  };

  const skip = (seconds: number) => {
    if (audioRef.current) {
      audioRef.current.currentTime = Math.max(
        0,
        Math.min(duration, audioRef.current.currentTime + seconds)
      );
    }
  };

  const formatTime = (seconds: number): string => {
    const mins = Math.floor(seconds / 60);
    const secs = Math.floor(seconds % 60);
    return `${mins}:${secs.toString().padStart(2, '0')}`;
  };

  if (!previewUrl || loadError) {
    return (
      <div className="flex flex-col items-center justify-center h-full text-theme-secondary">
        <div className="text-6xl mb-4">🎵</div>
        <p className="text-lg">Unable to load audio</p>
        <p className="text-sm text-theme-tertiary mt-2">{file.filename}</p>
      </div>
    );
  }

  return (
    <div className="flex flex-col items-center justify-center h-full p-8">
      <audio ref={audioRef} src={previewUrl} onError={() => setLoadError(true)} />

      {/* Album art placeholder */}
      <div className="w-64 h-64 rounded-2xl bg-gradient-to-br from-theme-primary/30 to-theme-secondary/30 flex items-center justify-center mb-8 shadow-lg">
        <div className="text-8xl">🎵</div>
      </div>

      {/* File info */}
      <h3 className="text-xl font-medium text-white mb-2 text-center max-w-md truncate">
        {file.filename}
      </h3>
      <p className="text-sm text-white/60 mb-8">
        {file.content_type} • {(file.file_size / 1024).toFixed(1)} KB
      </p>

      {/* Progress bar */}
      <div className="w-full max-w-lg mb-4">
        <input
          type="range"
          min={0}
          max={duration || 0}
          value={currentTime}
          onChange={handleSeek}
          className="w-full h-2 bg-white/20 rounded-lg appearance-none cursor-pointer accent-white"
        />
        <div className="flex justify-between mt-1">
          <span className="text-sm text-white/60">{formatTime(currentTime)}</span>
          <span className="text-sm text-white/60">{formatTime(duration)}</span>
        </div>
      </div>

      {/* Controls */}
      <div className="flex items-center space-x-6">
        <button
          onClick={() => skip(-10)}
          className="p-3 rounded-full hover:bg-white/10 transition-colors"
          title="Rewind 10 seconds"
        >
          <BackwardIcon className="w-6 h-6 text-white" />
        </button>

        <button
          onClick={togglePlay}
          className="p-4 rounded-full bg-white text-black hover:bg-white/90 transition-colors"
        >
          {isPlaying ? (
            <PauseIcon className="w-8 h-8" />
          ) : (
            <PlayIcon className="w-8 h-8 ml-1" />
          )}
        </button>

        <button
          onClick={() => skip(10)}
          className="p-3 rounded-full hover:bg-white/10 transition-colors"
          title="Forward 10 seconds"
        >
          <ForwardIcon className="w-6 h-6 text-white" />
        </button>
      </div>

      {/* Volume control */}
      <div className="flex items-center space-x-3 mt-8">
        <button
          onClick={toggleMute}
          className="p-2 rounded-full hover:bg-white/10 transition-colors"
        >
          {isMuted || volume === 0 ? (
            <SpeakerXMarkIcon className="w-5 h-5 text-white" />
          ) : (
            <SpeakerWaveIcon className="w-5 h-5 text-white" />
          )}
        </button>
        <input
          type="range"
          min={0}
          max={1}
          step={0.1}
          value={isMuted ? 0 : volume}
          onChange={handleVolumeChange}
          className="w-24 h-1 bg-white/20 rounded-lg appearance-none cursor-pointer accent-white"
        />
      </div>
    </div>
  );
};

export default FilePreviewAudio;
