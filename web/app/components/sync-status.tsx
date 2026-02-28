import { useEffect, useState } from "react";
import { usePowerSync } from "~/lib/powersync-provider";
import { Wifi, WifiOff, RefreshCw } from "lucide-react";
import { cn } from "~/lib/utils";

type SyncState = "disconnected" | "connecting" | "connected" | "syncing";

export function SyncStatus() {
  const db = usePowerSync();
  const [state, setState] = useState<SyncState>("disconnected");

  useEffect(() => {
    if (!db) {
      setState("disconnected");
      return;
    }

    setState("connecting");

    const check = () => {
      const status = db.currentStatus;
      if (status?.connected) {
        setState(status.dataFlowStatus?.downloading ? "syncing" : "connected");
      } else {
        setState("connecting");
      }
    };

    check();
    const interval = setInterval(check, 3000);
    return () => clearInterval(interval);
  }, [db]);

  const config: Record<SyncState, { icon: typeof Wifi; label: string; color: string }> = {
    disconnected: { icon: WifiOff, label: "Offline", color: "text-text-muted" },
    connecting: { icon: RefreshCw, label: "Connecting...", color: "text-warning" },
    connected: { icon: Wifi, label: "Synced", color: "text-success" },
    syncing: { icon: RefreshCw, label: "Syncing...", color: "text-accent" },
  };

  const { icon: Icon, label, color } = config[state];

  return (
    <div className={cn("flex items-center gap-2 px-3 py-2 text-xs", color)}>
      <Icon className={cn("h-3.5 w-3.5", state === "syncing" && "animate-spin")} />
      {label}
    </div>
  );
}
