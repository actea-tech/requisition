import type { UserRole } from "@/lib/supabase/database.types";
import { canAccessSettings, canViewAudit } from "@/lib/roles";

export interface NavItem {
  href: string;
  label: string;
  icon: "dashboard" | "plus" | "list" | "check" | "audit" | "settings";
}

export function navItemsForRole(role: UserRole): NavItem[] {
  const items: NavItem[] = [
    { href: "/", label: "Dashboard", icon: "dashboard" },
    { href: "/requisitions/new", label: "New Requisition", icon: "plus" },
    { href: "/requisitions", label: "My Requisitions", icon: "list" },
  ];

  if (role !== "staff") {
    items.push({ href: "/approvals", label: "Pending My Approval", icon: "check" });
  }

  if (canViewAudit(role)) {
    items.push({ href: "/audit", label: "Audit Trail", icon: "audit" });
  }

  if (canAccessSettings(role)) {
    items.push({ href: "/settings/departments", label: "Settings", icon: "settings" });
  }

  return items;
}
