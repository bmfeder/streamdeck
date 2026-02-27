import { redirect, useOutletContext } from "react-router";
import type { Route } from "./+types/login";
import { createSupabaseServerClient } from "~/lib/supabase.server";
import { getSupabaseBrowserClient } from "~/lib/supabase.client";
import type { AppContext } from "~/root";

export async function loader({ request }: Route.LoaderArgs) {
  const { supabase } = createSupabaseServerClient(request);
  const { data: { user } } = await supabase.auth.getUser();
  if (user) return redirect("/dashboard/playlists");
  return null;
}

export default function LoginPage() {
  const { env } = useOutletContext<AppContext>();

  const handleAppleSignIn = async () => {
    const supabase = getSupabaseBrowserClient(env);
    await supabase.auth.signInWithOAuth({
      provider: "apple",
      options: {
        redirectTo: `${window.location.origin}/auth/callback`,
      },
    });
  };

  return (
    <div className="flex min-h-screen items-center justify-center">
      <div className="w-full max-w-sm text-center">
        <div className="mb-8">
          <div className="mx-auto mb-4 h-16 w-16 rounded-2xl bg-accent" />
          <h1 className="text-3xl font-bold tracking-tight">
            Stream<span className="text-accent">Deck</span>
          </h1>
          <p className="mt-2 text-text-secondary">
            Manage your IPTV playlists from anywhere
          </p>
        </div>

        <button
          onClick={handleAppleSignIn}
          className="inline-flex w-full items-center justify-center gap-2 rounded-xl bg-white px-6 py-3 text-sm font-medium text-black transition-colors hover:bg-gray-100"
        >
          <svg className="h-5 w-5" viewBox="0 0 24 24" fill="currentColor">
            <path d="M17.05 20.28c-.98.95-2.05.88-3.08.4-1.09-.5-2.08-.48-3.24 0-1.44.62-2.2.44-3.06-.4C2.79 15.25 3.51 7.59 9.05 7.31c1.35.07 2.29.74 3.08.8 1.18-.24 2.31-.93 3.57-.84 1.51.12 2.65.72 3.4 1.8-3.12 1.87-2.38 5.98.48 7.13-.57 1.5-1.31 2.99-2.54 4.09zM12.03 7.25c-.15-2.23 1.66-4.07 3.74-4.25.29 2.58-2.34 4.5-3.74 4.25z" />
          </svg>
          Sign in with Apple
        </button>

        <p className="mt-6 text-xs text-text-muted">
          Your data syncs securely between devices via PowerSync
        </p>
      </div>
    </div>
  );
}
