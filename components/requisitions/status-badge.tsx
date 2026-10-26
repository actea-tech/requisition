import { Badge } from "@/components/ui/badge";
import { STATUS_BADGE_VARIANT, STATUS_LABELS, supervisorReviewLabel } from "@/lib/requisition-status";
import type { RequisitionStatus } from "@/lib/supabase/database.types";

export function StatusBadge({
  status,
  supervisorReview = false,
}: {
  status: RequisitionStatus;
  /** The department-review position is reviewed by supervisors the requester chose. */
  supervisorReview?: boolean;
}) {
  const label =
    supervisorReview && (status === "dept_review" || status === "procurement_dept_review")
      ? supervisorReviewLabel(STATUS_LABELS[status])
      : STATUS_LABELS[status];
  return <Badge variant={STATUS_BADGE_VARIANT[status]}>{label}</Badge>;
}
