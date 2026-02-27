import { useState, useEffect } from "react";
import { usePowerSync } from "~/lib/powersync-provider";

export function useQuery<T = Record<string, unknown>>(
  sql: string,
  params: unknown[] = []
) {
  const db = usePowerSync();
  const [data, setData] = useState<T[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<Error | null>(null);
  const paramsKey = JSON.stringify(params);

  useEffect(() => {
    if (!db) return;
    let active = true;
    const controller = new AbortController();

    async function run() {
      try {
        // PowerSync watch yields the full result set on each change
        for await (const result of db!.watch(sql, params, {
          signal: controller.signal,
        })) {
          if (!active) break;
          const rows = result?.rows?._array ?? (Array.isArray(result) ? result : []);
          setData(rows as T[]);
          setIsLoading(false);
        }
      } catch (err: unknown) {
        const e = err as Error;
        if (active && e?.name !== "AbortError") {
          setError(e instanceof Error ? e : new Error(String(e)));
          setIsLoading(false);
        }
      }
    }

    run();
    return () => {
      active = false;
      controller.abort();
    };
  }, [db, sql, paramsKey]);

  return { data, isLoading, error };
}
