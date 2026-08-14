import { SidebarTrigger } from "@/components/ui/sidebar";

export function AppHeader({ fullName }: { fullName: string }) {
  return (
    <header className="flex h-14 shrink-0 items-center gap-2 border-b bg-background px-4">
      <SidebarTrigger className="md:hidden" />
      <p className="text-sm font-medium">Welcome, {fullName}</p>
    </header>
  );
}
