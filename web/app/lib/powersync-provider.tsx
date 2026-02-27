import {
  createContext,
  useContext,
  useEffect,
  useRef,
  useState,
  type ReactNode,
} from "react";
import type { PowerSyncDatabase } from "@powersync/web";
import type { ClientEnv } from "./env";

const PSContext = createContext<PowerSyncDatabase | null>(null);

export function usePowerSync() {
  return useContext(PSContext);
}

export function PowerSyncProvider({
  env,
  children,
}: {
  env: ClientEnv;
  children: ReactNode;
}) {
  const [db, setDb] = useState<PowerSyncDatabase | null>(null);
  const initRef = useRef(false);

  useEffect(() => {
    if (initRef.current) return;
    initRef.current = true;

    (async () => {
      try {
        const { getPowerSync, connectPowerSync } = await import(
          "./powersync.client"
        );
        const database = getPowerSync(env);
        setDb(database);
        connectPowerSync(env).catch(console.error);
      } catch (err) {
        console.error("PowerSync init failed:", err);
      }
    })();
  }, [env]);

  return <PSContext.Provider value={db}>{children}</PSContext.Provider>;
}
