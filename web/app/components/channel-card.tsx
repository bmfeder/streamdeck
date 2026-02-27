import { Star, Play } from "lucide-react";
import { cn } from "~/lib/utils";

interface ChannelCardProps {
  id: string;
  name: string;
  groupName?: string;
  logoUrl?: string;
  channelNumber?: number;
  isFavorite: boolean;
  onToggleFavorite: () => void;
  onPlay: () => void;
}

export function ChannelCard({
  name,
  groupName,
  logoUrl,
  channelNumber,
  isFavorite,
  onToggleFavorite,
  onPlay,
}: ChannelCardProps) {
  return (
    <div className="group relative flex flex-col rounded-xl border border-border bg-surface-raised p-3 transition-colors hover:border-border-hover hover:bg-surface-overlay">
      {/* Logo / placeholder */}
      <div
        className="relative mb-3 flex aspect-video items-center justify-center overflow-hidden rounded-lg bg-surface"
        onClick={onPlay}
        role="button"
        tabIndex={0}
        onKeyDown={(e) => e.key === "Enter" && onPlay()}
      >
        {logoUrl ? (
          <img
            src={logoUrl}
            alt={name}
            className="h-full w-full object-contain p-2"
            loading="lazy"
          />
        ) : (
          <span className="text-3xl font-bold text-text-muted">
            {channelNumber ?? name.charAt(0)}
          </span>
        )}
        <div className="absolute inset-0 flex items-center justify-center bg-black/50 opacity-0 transition-opacity group-hover:opacity-100">
          <Play className="h-8 w-8 text-accent" fill="currentColor" />
        </div>
      </div>

      {/* Info */}
      <div className="flex items-start justify-between gap-2">
        <div className="min-w-0 flex-1">
          <p className="truncate text-sm font-medium text-text-primary">{name}</p>
          {groupName && (
            <p className="truncate text-xs text-text-secondary">{groupName}</p>
          )}
        </div>
        <button
          onClick={(e) => {
            e.stopPropagation();
            onToggleFavorite();
          }}
          className={cn(
            "shrink-0 rounded-md p-1 transition-colors",
            isFavorite
              ? "text-accent"
              : "text-text-muted hover:text-text-secondary"
          )}
        >
          <Star
            className="h-4 w-4"
            fill={isFavorite ? "currentColor" : "none"}
          />
        </button>
      </div>
    </div>
  );
}
