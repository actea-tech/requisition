import { Badge } from "@/components/ui/badge";
import { STATUS_BADGE_VARIANT, statusLabel } from "@/lib/requisition-status";
import type { RequisitionStatus } from "@/lib/supabase/database.types";

export function StatusBadge({
  status,
  invoiceSubmitted = false,
}: {
  status: RequisitionStatus;
  /** Set for a procurement requisition that has already passed through the invoice step once (requires_full_reapproval restart). */
  invoiceSubmitted?: boolean;
}) {
  return <Badge variant={STATUS_BADGE_VARIANT[status]}>{statusLabel(status, invoiceSubmitted)}</Badge>;
}
