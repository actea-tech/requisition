import { requireAdmin } from "@/lib/auth/session";
import { SettingsNav } from "@/components/settings/settings-nav";

export default async function SettingsLayout({ children }: { children: React.ReactNode }) {
  await requireAdmin();

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-semibold">Settings</h1>
        <p className="text-sm text-muted-foreground">
          Departments, people, form fields, and approval rules for the requisition workflow.
        </p>
      </div>
      <SettingsNav />
      <div>{children}</div>
    </div>
  );
}
