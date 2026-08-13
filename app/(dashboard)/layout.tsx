import { AppHeader } from "@/components/layout/app-header";
import { AppSidebar } from "@/components/layout/app-sidebar";
import { SidebarInset, SidebarProvider } from "@/components/ui/sidebar";
import { requireProfile } from "@/lib/auth/session";
import { navItemsForRole } from "@/lib/nav";

export default async function DashboardLayout({ children }: { children: React.ReactNode }) {
  const profile = await requireProfile();

  return (
    <SidebarProvider>
      <AppSidebar items={navItemsForRole(profile.role)} fullName={profile.full_name} role={profile.role} />
      <SidebarInset>
        <AppHeader fullName={profile.full_name} />
        <main className="flex-1 p-6">{children}</main>
      </SidebarInset>
    </SidebarProvider>
  );
}
