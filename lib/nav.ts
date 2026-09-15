import type { UserRole } from "@/lib/supabase/database.types";
import { canAccessSettings, canViewAudit } from "@/lib/roles";

export interface NavItem {
  href: string;
  label: string;
  icon: "dashboard" | "plus" | "list" | "accounting" | "check" | "audit" | "settings";
}

export function navItemsForRole(role: UserRole): NavItem[] {
  const items: NavItem[] = [
    { href: "/", label: "Dashboard", icon: "dashboard" },
    { href: "/requisitions/new", label: "New Requisition", icon: "plus" },
    { href: "/requisitions", label: "My Requisitions", icon: "list" },
    // Fund requisitions specifically at the accounting stage — the same
    // tab as My Requisitions' "Accounting" tab, just reachable directly.
    { href: "/requisitions?tab=accounting", label: "Needs My Accounting", icon: "accounting" },
  ];

  // Shown to everyone, not just non-"staff" roles: a department head's
  // actual eligibility comes from department_heads membership (see
  // migration 0015), which can be true even when the role label wasn't
  // updated to "dept_head". Worst case for a plain staff member is an
  // empty list.
  items.push({ href: "/approvals", label: "Pending My Approval", icon: "check" });

  if (canViewAudit(role)) {
    items.push({ href: "/audit", label: "Audit Trail", icon: "audit" });
  }

  if (canAccessSettings(role)) {
    items.push({ href: "/settings/departments", label: "Settings", icon: "settings" });
  }

  return items;
}
