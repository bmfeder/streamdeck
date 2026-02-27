import { useState } from "react";
import { X } from "lucide-react";
import { cn } from "~/lib/utils";

type PlaylistType = "m3u" | "xtream" | "emby";

interface AddPlaylistDialogProps {
  open: boolean;
  onClose: () => void;
  onSubmit: (data: PlaylistFormData) => void;
}

export interface PlaylistFormData {
  name: string;
  type: PlaylistType;
  url: string;
  username?: string;
  password?: string;
  epgUrl?: string;
  refreshHrs: number;
}

export function AddPlaylistDialog({ open, onClose, onSubmit }: AddPlaylistDialogProps) {
  const [type, setType] = useState<PlaylistType>("m3u");
  const [name, setName] = useState("");
  const [url, setUrl] = useState("");
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [epgUrl, setEpgUrl] = useState("");
  const [refreshHrs, setRefreshHrs] = useState(24);
  const [errors, setErrors] = useState<Record<string, string>>({});

  if (!open) return null;

  const validate = (): boolean => {
    const errs: Record<string, string> = {};
    if (!name.trim()) errs.name = "Name is required";
    if (!url.trim()) errs.url = type === "m3u" ? "M3U URL is required" : "Server URL is required";
    if (type !== "m3u" && !username.trim()) errs.username = "Username is required";
    if (type !== "m3u" && !password.trim()) errs.password = "Password is required";
    setErrors(errs);
    return Object.keys(errs).length === 0;
  };

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (!validate()) return;
    onSubmit({
      name: name.trim(),
      type,
      url: url.trim(),
      username: type !== "m3u" ? username.trim() : undefined,
      password: type !== "m3u" ? password.trim() : undefined,
      epgUrl: epgUrl.trim() || undefined,
      refreshHrs,
    });
    // Reset
    setName(""); setUrl(""); setUsername(""); setPassword(""); setEpgUrl(""); setRefreshHrs(24);
    setType("m3u"); setErrors({});
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60" onClick={onClose}>
      <div
        className="w-full max-w-lg rounded-xl border border-border bg-surface-raised p-6"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="mb-6 flex items-center justify-between">
          <h2 className="text-lg font-semibold">Add Source</h2>
          <button onClick={onClose} className="rounded-md p-1 text-text-secondary hover:text-text-primary">
            <X className="h-5 w-5" />
          </button>
        </div>

        <form onSubmit={handleSubmit} className="space-y-4">
          {/* Type selector */}
          <div className="flex gap-2">
            {(["m3u", "xtream", "emby"] as const).map((t) => (
              <button
                key={t}
                type="button"
                onClick={() => setType(t)}
                className={cn(
                  "rounded-lg px-4 py-2 text-sm font-medium transition-colors",
                  type === t
                    ? "bg-accent text-surface"
                    : "bg-surface-overlay text-text-secondary hover:text-text-primary"
                )}
              >
                {t === "m3u" ? "M3U" : t === "xtream" ? "Xtream" : "Emby"}
              </button>
            ))}
          </div>

          {/* Name */}
          <Field label="Name" error={errors.name}>
            <input
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder="My Playlist"
              className="input"
            />
          </Field>

          {/* URL */}
          <Field
            label={type === "m3u" ? "M3U URL" : "Server URL"}
            error={errors.url}
          >
            <input
              value={url}
              onChange={(e) => setUrl(e.target.value)}
              placeholder={type === "m3u" ? "https://example.com/playlist.m3u" : "https://provider.com"}
              className="input"
            />
          </Field>

          {/* Username/Password for Xtream/Emby */}
          {type !== "m3u" && (
            <>
              <Field label="Username" error={errors.username}>
                <input
                  value={username}
                  onChange={(e) => setUsername(e.target.value)}
                  className="input"
                />
              </Field>
              <Field label="Password" error={errors.password}>
                <input
                  type="password"
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                  className="input"
                />
              </Field>
            </>
          )}

          {/* EPG URL */}
          <Field label="EPG URL (optional)">
            <input
              value={epgUrl}
              onChange={(e) => setEpgUrl(e.target.value)}
              placeholder="https://example.com/epg.xml"
              className="input"
            />
          </Field>

          {/* Refresh interval */}
          <Field label="Auto-refresh">
            <select
              value={refreshHrs}
              onChange={(e) => setRefreshHrs(Number(e.target.value))}
              className="input"
            >
              <option value={6}>Every 6 hours</option>
              <option value={12}>Every 12 hours</option>
              <option value={24}>Every 24 hours</option>
              <option value={48}>Every 48 hours</option>
              <option value={0}>Manual only</option>
            </select>
          </Field>

          {/* Actions */}
          <div className="flex justify-end gap-3 pt-2">
            <button
              type="button"
              onClick={onClose}
              className="rounded-lg px-4 py-2 text-sm text-text-secondary hover:bg-surface-hover hover:text-text-primary"
            >
              Cancel
            </button>
            <button
              type="submit"
              className="rounded-lg bg-accent px-4 py-2 text-sm font-medium text-surface hover:bg-accent-hover transition-colors"
            >
              Add Source
            </button>
          </div>
        </form>
      </div>

      <style>{`
        .input {
          width: 100%;
          border-radius: 0.5rem;
          border: 1px solid var(--color-border);
          background: var(--color-surface);
          padding: 0.5rem 0.75rem;
          font-size: 0.875rem;
          color: var(--color-text-primary);
        }
        .input:focus {
          outline: none;
          border-color: var(--color-accent);
        }
        .input::placeholder {
          color: var(--color-text-muted);
        }
      `}</style>
    </div>
  );
}

function Field({
  label,
  error,
  children,
}: {
  label: string;
  error?: string;
  children: React.ReactNode;
}) {
  return (
    <div>
      <label className="mb-1.5 block text-sm font-medium text-text-secondary">
        {label}
      </label>
      {children}
      {error && <p className="mt-1 text-xs text-danger">{error}</p>}
    </div>
  );
}
