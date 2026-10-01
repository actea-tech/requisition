import type { RequisitionKind, RequisitionStatus } from "@/lib/supabase/database.types";

// The canonical, full list — includes accounting_review, which only a Fund
// requisition ever actually passes through. Used as-is for things like the
// audit filter dropdown; use getStatusSteps for a per-requisition stepper
// so a plain Payment requisition doesn't show a step it never took.
export const STATUS_STEPS: { status: RequisitionStatus; label: string }[] = [
  { status: "draft", label: "Draft" },
  { status: "dept_review", label: "Department Review" },
  { status: "procurement_dept_review", label: "Procurement — Department Review" },
  { status: "procurement_finance_review", label: "Procurement — Finance Review" },
  { status: "awaiting_invoice", label: "Awaiting Invoice" },
  { status: "finance_review", label: "Finance Review" },
  { status: "director_review", label: "Authorization" },
  { status: "approved_for_payment", label: "Payment Processing" },
  { status: "paid_posted", label: "Paid" },
  { status: "accounting_review", label: "Accounting Review" },
  { status: "posted_and_closed", label: "Posted & Closed" },
];

const PROCUREMENT_ONLY_STATUSES = new Set<RequisitionStatus>([
  "procurement_dept_review",
  "procurement_finance_review",
  "awaiting_invoice",
]);

export function getStatusSteps(kind: RequisitionKind) {
  return STATUS_STEPS.filter((s) => {
    if (s.status === "accounting_review") return kind === "fund";
    if (PROCUREMENT_ONLY_STATUSES.has(s.status)) return kind === "procurement";
    if (s.status === "dept_review") return kind !== "procurement";
    return true;
  });
}

export const STATUS_LABELS: Record<RequisitionStatus, string> = {
  draft: "Draft",
  dept_review: "Department Review",
  procurement_dept_review: "Procurement — Department Review",
  procurement_finance_review: "Procurement — Finance Review",
  awaiting_invoice: "Awaiting Invoice",
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

// requires_full_reapproval restarts a procurement requisition at
// procurement_dept_review/procurement_finance_review a *second* time,
// post-invoice — at that point it's reviewing the real numbers, not the
// original pre-invoice pass, so it reads as plain "Department Review"/
// "Finance Review" rather than the "Procurement — " prefixed label used
// the first time through.
export function statusLabel(status: RequisitionStatus, invoiceSubmitted: boolean): string {
  if (invoiceSubmitted) {
    if (status === "procurement_dept_review") return "Department Review";
    if (status === "procurement_finance_review") return "Finance Review";
  }
  return STATUS_LABELS[status];
}

export const STATUS_BADGE_VARIANT: Record<RequisitionStatus, "default" | "secondary" | "destructive" | "success" | "warning"> = {
  draft: "secondary",
  dept_review: "warning",
  procurement_dept_review: "warning",
  procurement_finance_review: "warning",
  awaiting_invoice: "warning",
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
    case "procurement_dept_review":
      return "department";
    case "finance_review":
    case "procurement_finance_review":
      return "finance";
    case "director_review":
      return "director";
    case "approved_for_payment":
      return "payment";
    default:
      return null;
  }
}
