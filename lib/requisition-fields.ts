export type FieldInputType = "text" | "textarea" | "number" | "select";

export interface FieldSpec {
  type: FieldInputType;
  options?: { value: string; label: string }[];
}

const YES_NO = [
  { value: "yes", label: "Yes" },
  { value: "no", label: "No" },
];

const YES_NO_UNSURE = [...YES_NO, { value: "not_sure", label: "Not sure" }];

const CURRENCIES = ["KES", "USD", "EUR", "GBP", "UGX", "TZS"].map((c) => ({ value: c, label: c }));

const PAYMENT_MODES = ["Bank transfer", "M-Pesa", "Cheque", "Petty cash", "Other"].map((v) => ({
  value: v,
  label: v,
}));

const PAYMENT_STATUSES = [
  { value: "pending", label: "Pending" },
  { value: "approved_for_payment", label: "Approved for payment" },
  { value: "paid", label: "Paid" },
  { value: "posted_in_qbo", label: "Posted in QBO" },
  { value: "returned", label: "Returned" },
];

export const FIELD_SPECS: Record<string, FieldSpec> = {
  purpose: { type: "textarea" },
  activity_project: { type: "text" },
  payee_name: { type: "text" },
  payee_contact: { type: "text" },
  amount: { type: "number" },
  currency: { type: "select", options: CURRENCIES },
  payment_mode: { type: "select", options: PAYMENT_MODES },
  budget_line: { type: "text" },
  account_code: { type: "text" },
  project_fund_class_code: { type: "text" },
  donor_grant_source: { type: "text" },
  budgeted: { type: "select", options: YES_NO },
  procurement_required: { type: "select", options: YES_NO },
  donor_restriction: { type: "select", options: YES_NO_UNSURE },
  outstanding_advance: { type: "select", options: YES_NO },
  finance_comments: { type: "textarea" },
  budget_available: { type: "select", options: YES_NO },
  director_comments: { type: "textarea" },
  payment_voucher_number: { type: "text" },
  qbo_posting_reference: { type: "text" },
  payment_status: { type: "select", options: PAYMENT_STATUSES },
};
