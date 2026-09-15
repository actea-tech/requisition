import type { RequisitionKind, RequisitionStatus } from "@/lib/supabase/database.types";

// The canonical, full list — includes accounting_review, which only a Fund
// requisition ever actually passes through. Used as-is for things like the
// audit filter dropdown; use getStatusSteps for a per-requisition stepper
// so a plain Payment requisition doesn't show a step it never took.
export const STATUS_STEPS: { status: RequisitionStatus; label: string }[] = [
  { status: "draft", label: "Draft" },
  { status: "dept_review", label: "Department Review" },
  { status: "finance_review", label: "Finance Review" },
  { status: "director_review", label: "Authorization" },
  { status: "approved_for_payment", label: "Payment Processing" },
  { status: "paid_posted", label: "Paid" },
  { status: "accounting_review", label: "Accounting Review" },
  { status: "posted_and_closed", label: "Posted & Closed" },
];

export function getStatusSteps(kind: RequisitionKind) {
  return kind === "fund" ? STATUS_STEPS : STATUS_STEPS.filter((s) => s.status !== "accounting_review");
}

export const STATUS_LABELS: Record<RequisitionStatus, string> = {
  draft: "Draft",
  dept_review: "Department Review",
  finance_review: "Finance Review",
  director_review: "Authorization",
  approved_for_payment: "Payment Processing",
  paid_posted: "Paid",
  accounting_review: "Accounting Review",
  posted_and_closed: "Posted & Closed",
  returned: "Returned for Correction",
  rejected: "Rejected",
  cancelled: "Cancelled",
};

export const STATUS_BADGE_VARIANT: Record<RequisitionStatus, "default" | "secondary" | "destructive" | "success" | "warning"> = {
  draft: "secondary",
  dept_review: "warning",
  finance_review: "warning",
  director_review: "warning",
  approved_for_payment: "warning",
  paid_posted: "warning",
  accounting_review: "warning",
  posted_and_closed: "success",
  returned: "destructive",
  rejected: "destructive",
  cancelled: "destructive",
};

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
