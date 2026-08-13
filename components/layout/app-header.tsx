import { LogOut } from "lucide-react";
import { signOut } from "@/app/login/actions";
import { Button } from "@/components/ui/button";
import { SidebarTrigger } from "@/components/ui/sidebar";
import { Separator } from "@/components/ui/separator";

export function AppHeader({ fullName }: { fullName: string }) {
  return (
    <header className="flex h-14 shrink-0 items-center gap-2 border-b bg-background px-4">
      <SidebarTrigger />
      <Separator orientation="vertical" className="h-5" />
      <p className="text-sm font-medium">Welcome, {fullName}</p>
      <form action={signOut} className="ml-auto">
        <Button type="submit" variant="ghost" size="sm">
          <LogOut className="size-4" />
          Sign out
        </Button>
      </form>
    </header>
  );
}
