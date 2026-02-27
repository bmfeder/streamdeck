import { Outlet, redirect, useOutletContext } from "react-router";
import type { Route } from "./+types/dashboard";
import { createSupabaseServerClient } from "~/lib/supabase.server";
import type { AppContext } from "~/root";
import { PowerSyncProvider } from "~/lib/powersync-provider";
import { Sidebar } from "~/components/sidebar";
import { Topbar } from "~/components/topbar";
import { useAuth } from "~/hooks/use-auth";

export async function loader({ request }: Route.LoaderArgs) {
  const { supabase } = createSupabaseServerClient(request);
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) throw redirect("/login");
  return { user: { email: user.email, user_metadata: user.user_metadata } };
}

export default function DashboardLayout({ loaderData }: Route.ComponentProps) {
  const { env } = useOutletContext<AppContext>();
  const { signOut } = useAuth();

  return (
    <PowerSyncProvider env={env}>
      <div className="min-h-screen bg-surface">
        <Sidebar />
        <Topbar user={loaderData.user} onSignOut={signOut} />
        <main className="ml-60 pt-14">
          <div className="p-6">
            <Outlet context={{ env } satisfies AppContext} />
          </div>
        </main>
      </div>
    </PowerSyncProvider>
  );
}
