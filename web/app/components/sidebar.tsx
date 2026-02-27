import { NavLink } from "react-router";
import {
  HardDrive,
  Tv,
  Film,
  MonitorPlay,
  Clock,
  Settings,
} from "lucide-react";
import { cn } from "~/lib/utils";
import { SyncStatus } from "./sync-status";

const navItems = [
  { to: "/dashboard/playlists", label: "Sources", icon: HardDrive },
  { to: "/dashboard/channels", label: "Live TV", icon: Tv },
  { to: "/dashboard/movies", label: "Movies", icon: Film },
  { to: "/dashboard/tvshows", label: "TV Shows", icon: MonitorPlay },
  { to: "/dashboard/progress", label: "History", icon: Clock },
  { to: "/dashboard/settings", label: "Settings", icon: Settings },
];

export function Sidebar() {
  return (
    <aside className="fixed inset-y-0 left-0 z-30 flex w-60 flex-col border-r border-border bg-surface-raised">
      <div className="flex h-14 items-center gap-2 border-b border-border px-4">
        <div className="h-7 w-7 rounded-lg bg-accent" />
        <span className="text-lg font-semibold tracking-tight">
          Stream<span className="text-accent">Deck</span>
        </span>
      </div>

      <nav className="flex-1 space-y-1 p-3">
        {navItems.map((item) => (
          <NavLink
            key={item.to}
            to={item.to}
            className={({ isActive }) =>
              cn(
                "flex items-center gap-3 rounded-lg px-3 py-2.5 text-sm font-medium transition-colors",
                isActive
                  ? "bg-accent/10 text-accent"
                  : "text-text-secondary hover:bg-surface-hover hover:text-text-primary"
              )
            }
          >
            <item.icon className="h-4.5 w-4.5 shrink-0" />
            {item.label}
          </NavLink>
        ))}
      </nav>

      <div className="border-t border-border p-3">
        <SyncStatus />
      </div>
    </aside>
  );
}
