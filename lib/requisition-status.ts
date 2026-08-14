import type { RequisitionStatus } from "@/lib/supabase/database.types";

export const STATUS_STEPS: { status: RequisitionStatus; label: string }[] = [
  { status: "draft", label: "Draft" },
  { status: "dept_review", label: "Department Review" },
  { status: "finance_review", label: "Finance Review" },
  { status: "director_review", label: "Director Authorization" },
  { status: "approved_for_payment", label: "Payment Processing" },
  { status: "paid_posted", label: "Paid / Posted" },
];

export const STATUS_LABELS: Record<RequisitionStatus, string> = {
  draft: "Draft",
  dept_review: "Department Review",
  finance_review: "Finance Review",
  director_review: "Director Authorization",
  approved_for_payment: "Payment Processing",
  paid_posted: "Paid / Posted",
  returned: "Returned for Correction",
  rejected: "Rejected",
};

export const STATUS_BADGE_VARIANT: Record<RequisitionStatus, "default" | "secondary" | "destructive" | "success" | "warning"> = {
  draft: "secondary",
  dept_review: "warning",
  finance_review: "warning",
  director_review: "warning",
  approved_for_payment: "warning",
  paid_posted: "success",
  returned: "destructive",
  rejected: "destructive",
};

// "Pending my approval" must also catch requisitions returned to a
// previous stage (return_to='previous_stage') — those sit at
// status='returned', not one of the active review statuses, but still
// need that stage's action. RLS is still the real authority on who can
// actually see each row; this just widens the status filter.
export const PENDING_APPROVAL_OR_FILTER =
  "status.in.(dept_review,finance_review,director_review,approved_for_payment),and(status.eq.returned,return_to.eq.previous_stage)";

export function stageKeyForStatus(status: RequisitionStatus): "department" | "finance" | "director" | "payment" | null {
  switch (status) {
    case "dept_review":
      return "department";
    case "finance_review":
      return "finance";
    case "director_review":
      return "director";
    case "approved_for_payment":
      return "payment";
    default:
      return null;
  }
}
