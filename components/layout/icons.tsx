import {
  LayoutDashboard,
  PlusCircle,
  ListChecks,
  ClipboardCheck,
  ScrollText,
  Settings,
  type LucideIcon,
} from "lucide-react";
import type { NavItem } from "@/lib/nav";

const ICONS: Record<NavItem["icon"], LucideIcon> = {
  dashboard: LayoutDashboard,
  plus: PlusCircle,
  list: ListChecks,
  check: ClipboardCheck,
  audit: ScrollText,
  settings: Settings,
};

export function NavIcon({ icon, className }: { icon: NavItem["icon"]; className?: string }) {
  const Icon = ICONS[icon];
  return <Icon className={className} />;
}
