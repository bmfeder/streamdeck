import { useState } from "react";
import { useNavigate } from "react-router";
import { Search, LogOut, User } from "lucide-react";
import { cn } from "~/lib/utils";

interface TopbarProps {
  user: { email?: string; user_metadata?: { full_name?: string } } | null;
  onSignOut: () => void;
}

export function Topbar({ user, onSignOut }: TopbarProps) {
  const [query, setQuery] = useState("");
  const navigate = useNavigate();

  const handleSearch = (e: React.FormEvent) => {
    e.preventDefault();
    if (query.trim()) {
      navigate(`/dashboard/channels?q=${encodeURIComponent(query.trim())}`);
    }
  };

  const displayName =
    user?.user_metadata?.full_name || user?.email || "User";

  return (
    <header className="fixed inset-x-0 top-0 z-20 ml-60 flex h-14 items-center justify-between border-b border-border bg-surface-raised px-6">
      <form onSubmit={handleSearch} className="relative w-80">
        <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-text-muted" />
        <input
          type="text"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          placeholder="Search channels, movies..."
          className="w-full rounded-lg border border-border bg-surface py-2 pl-10 pr-4 text-sm text-text-primary placeholder:text-text-muted focus:border-accent focus:outline-none"
        />
      </form>

      <div className="flex items-center gap-3">
        <div className="flex items-center gap-2 text-sm text-text-secondary">
          <User className="h-4 w-4" />
          <span className="max-w-[150px] truncate">{displayName}</span>
        </div>
        <button
          onClick={onSignOut}
          className={cn(
            "flex items-center gap-1.5 rounded-lg px-3 py-1.5 text-sm",
            "text-text-secondary hover:bg-surface-hover hover:text-text-primary transition-colors"
          )}
        >
          <LogOut className="h-4 w-4" />
          Sign Out
        </button>
      </div>
    </header>
  );
}
