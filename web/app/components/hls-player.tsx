import { useEffect, useRef, useState } from "react";
import { X, Volume2, VolumeX, Maximize, Minimize } from "lucide-react";
import { cn } from "~/lib/utils";

interface HlsPlayerProps {
  url: string;
  title?: string;
  onClose: () => void;
}

export function HlsPlayer({ url, title, onClose }: HlsPlayerProps) {
  const videoRef = useRef<HTMLVideoElement>(null);
  const hlsRef = useRef<any>(null);
  const [muted, setMuted] = useState(false);
  const [expanded, setExpanded] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const video = videoRef.current;
    if (!video) return;

    let hls: any = null;

    (async () => {
      try {
        const Hls = (await import("hls.js")).default;

        if (Hls.isSupported()) {
          hls = new Hls({
            enableWorker: true,
            lowLatencyMode: true,
          });
          hls.loadSource(url);
          hls.attachMedia(video);
          hls.on(Hls.Events.ERROR, (_: any, data: any) => {
            if (data.fatal) {
              setError(`Playback error: ${data.details}`);
            }
          });
          hlsRef.current = hls;
        } else if (video.canPlayType("application/vnd.apple.mpegurl")) {
          // Safari native HLS
          video.src = url;
        } else {
          setError("HLS not supported in this browser");
        }

        video.play().catch(() => {
          // Autoplay blocked — user will click play
        });
      } catch (err) {
        setError("Failed to load player");
      }
    })();

    return () => {
      hls?.destroy();
      hlsRef.current = null;
    };
  }, [url]);

  useEffect(() => {
    if (videoRef.current) {
      videoRef.current.muted = muted;
    }
  }, [muted]);

  return (
    <div
      className={cn(
        "overflow-hidden rounded-xl border border-border bg-surface-raised",
        expanded ? "fixed inset-4 z-50" : "relative"
      )}
    >
      {/* Header */}
      <div className="flex items-center justify-between border-b border-border bg-surface-overlay px-3 py-2">
        <span className="truncate text-sm font-medium text-text-primary">
          {title || "Live Preview"}
        </span>
        <div className="flex items-center gap-1">
          <button
            onClick={() => setMuted(!muted)}
            className="rounded-md p-1.5 text-text-secondary hover:bg-surface-hover hover:text-text-primary"
          >
            {muted ? (
              <VolumeX className="h-4 w-4" />
            ) : (
              <Volume2 className="h-4 w-4" />
            )}
          </button>
          <button
            onClick={() => setExpanded(!expanded)}
            className="rounded-md p-1.5 text-text-secondary hover:bg-surface-hover hover:text-text-primary"
          >
            {expanded ? (
              <Minimize className="h-4 w-4" />
            ) : (
              <Maximize className="h-4 w-4" />
            )}
          </button>
          <button
            onClick={onClose}
            className="rounded-md p-1.5 text-text-secondary hover:bg-surface-hover hover:text-text-primary"
          >
            <X className="h-4 w-4" />
          </button>
        </div>
      </div>

      {/* Video */}
      <div className="relative aspect-video bg-black">
        {error ? (
          <div className="flex h-full items-center justify-center text-sm text-danger">
            {error}
          </div>
        ) : (
          <video
            ref={videoRef}
            className="h-full w-full"
            playsInline
            autoPlay
          />
        )}
      </div>
    </div>
  );
}
