import { useState, useEffect, useCallback } from "react";
import { useOutletContext } from "react-router";
import type { AuthChangeEvent, Session, User } from "@supabase/supabase-js";
import type { AppContext } from "~/root";
import { getSupabaseBrowserClient } from "~/lib/supabase.client";

export function useAuth() {
  const { env } = useOutletContext<AppContext>();
  const [user, setUser] = useState<User | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const supabase = getSupabaseBrowserClient(env);

    void supabase.auth.getUser().then(
      (result: { data: { user: User | null }; error: unknown }) => {
        setUser(result.data.user);
        setLoading(false);
      }
    );

    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange(
      (_event: AuthChangeEvent, session: Session | null) => {
        setUser(session?.user ?? null);
      }
    );

    return () => subscription.unsubscribe();
  }, [env]);

  const signInWithApple = useCallback(async () => {
    const supabase = getSupabaseBrowserClient(env);
    await supabase.auth.signInWithOAuth({
      provider: "apple",
      options: {
        redirectTo: `${window.location.origin}/auth/callback`,
      },
    });
  }, [env]);

  const signOut = useCallback(async () => {
    const supabase = getSupabaseBrowserClient(env);
    await supabase.auth.signOut();
    window.location.href = "/login";
  }, [env]);

  return { user, loading, signInWithApple, signOut };
}
