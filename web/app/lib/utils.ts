import { clsx, type ClassValue } from "clsx";
import { twMerge } from "tailwind-merge";

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

export function formatDuration(seconds: number): string {
  const h = Math.floor(seconds / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  if (h > 0) return `${h}h ${m}m`;
  return `${m}m`;
}

export function formatProgress(positionMs: number, durationMs: number | null): string {
  if (!durationMs || durationMs <= 0) return "";
  const pct = Math.round((positionMs / durationMs) * 100);
  return `${pct}%`;
}
