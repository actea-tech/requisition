// Hand-written to match supabase/migrations/*.sql. Once the schema is
// applied, regenerate the authoritative version with:
//   npx supabase gen types typescript --project-id trpsghzizbnxewnellat > lib/supabase/database.types.ts
// and diff it against this file — column names/types here should match.
export type Json = string | number | boolean | null | { [key: string]: Json | undefined } | Json[];

export type UserRole = "staff" | "dept_head" | "finance_accountant" | "finance_reviewer" | "director" | "admin";
export type ApprovalMode = "first_approver" | "all_approvers" | "quorum";
export type ApprovalStageKey = "department" | "finance" | "director" | "payment";
export type ApprovalDecision = "submitted" | "approved" | "returned" | "rejected" | "completed";
export type RequisitionStatus =
  | "draft"
  | "dept_review"
  | "finance_review"
  | "director_review"
  | "approved_for_payment"
  | "paid_posted"
  | "returned"
  | "rejected";
export type YesNo = "yes" | "no";
export type YesNoUnsure = "yes" | "no" | "not_sure";
export type EmailStatus = "pending" | "sent" | "failed";
export type FormSection =
  | "request_details"
  | "payment_details"
  | "budget_and_coding"
  | "compliance_and_support"
  | "finance_review"
  | "final_processing";

export interface Database {
  public: {
    Tables: {
      departments: {
        Row: { id: string; name: string; is_active: boolean; created_at: string };
        Insert: { id?: string; name: string; is_active?: boolean; created_at?: string };
        Update: Partial<{ id: string; name: string; is_active: boolean }>;
        Relationships: [];
      };
      profiles: {
        Row: {
          id: string;
          full_name: string;
          email: string;
          role: UserRole;
          department_id: string | null;
          is_active: boolean;
          must_change_password: boolean;
          created_at: string;
          updated_at: string;
        };
        Insert: {
          id: string;
          full_name: string;
          email: string;
          role?: UserRole;
          department_id?: string | null;
          is_active?: boolean;
        };
        Update: Partial<{ full_name: string; role: UserRole; department_id: string | null; is_active: boolean }>;
        Relationships: [];
      };
      department_heads: {
        Row: { department_id: string; user_id: string; created_at: string };
        Insert: { department_id: string; user_id: string };
        Update: Partial<{ department_id: string; user_id: string }>;
        Relationships: [];
      };
      approval_stage_config: {
        Row: {
          id: string;
          stage_key: ApprovalStageKey;
          department_id: string | null;
          mode: ApprovalMode;
          quorum_count: number | null;
          created_at: string;
          updated_at: string;
        };
        Insert: {
          id?: string;
          stage_key: ApprovalStageKey;
          department_id?: string | null;
          mode?: ApprovalMode;
          quorum_count?: number | null;
        };
        Update: Partial<{ mode: ApprovalMode; quorum_count: number | null }>;
        Relationships: [];
      };
      form_field_config: {
        Row: {
          id: string;
          section: FormSection;
          field_key: string;
          label: string;
          help_text: string | null;
          is_visible: boolean;
          is_required: boolean;
          sort_order: number;
          created_at: string;
          updated_at: string;
        };
        Insert: {
          id?: string;
          section: FormSection;
          field_key: string;
          label: string;
          help_text?: string | null;
          is_visible?: boolean;
          is_required?: boolean;
          sort_order?: number;
        };
        Update: Partial<{ label: string; help_text: string | null; is_visible: boolean; is_required: boolean; sort_order: number }>;
        Relationships: [];
      };
      requisitions: {
        Row: {
          id: string;
          requisition_number: string | null;
          requester_id: string;
          department_id: string;
          status: RequisitionStatus;
          purpose: string | null;
          activity_project: string | null;
          payee_name: string | null;
          payee_contact: string | null;
          amount: number | null;
          currency: string;
          payment_mode: string | null;
          budget_line: string | null;
          account_code: string | null;
          project_fund_class_code: string | null;
          donor_grant_source: string | null;
          budgeted: YesNo | null;
          procurement_required: YesNo | null;
          donor_restriction: YesNoUnsure | null;
          outstanding_advance: YesNo | null;
          finance_comments: string | null;
          budget_available: YesNo | null;
          finance_cleared: boolean;
          finance_accountant_id: string | null;
          director_comments: string | null;
          director_decision: "approved" | "returned" | "rejected" | null;
          director_id: string | null;
          payment_voucher_number: string | null;
          qbo_posting_reference: string | null;
          payment_status: "pending" | "approved_for_payment" | "paid" | "posted_in_qbo" | "returned";
          returned_from_stage: RequisitionStatus | null;
          return_reason: string | null;
          return_to: "requester" | "previous_stage";
          requires_reapproval: boolean;
          stage_entered_at: string;
          submitted_at: string | null;
          created_at: string;
          updated_at: string;
        };
        Insert: {
          id?: string;
          requisition_number?: string;
          requester_id: string;
          department_id: string;
          purpose?: string | null;
          activity_project?: string | null;
          payee_name?: string | null;
          payee_contact?: string | null;
          amount?: number | null;
          currency?: string;
          payment_mode?: string | null;
          budget_line?: string | null;
          account_code?: string | null;
          project_fund_class_code?: string | null;
          donor_grant_source?: string | null;
          budgeted?: YesNo | null;
          procurement_required?: YesNo | null;
          donor_restriction?: YesNoUnsure | null;
          outstanding_advance?: YesNo | null;
        };
        Update: Partial<{
          purpose: string | null;
          activity_project: string | null;
          payee_name: string | null;
          payee_contact: string | null;
          amount: number | null;
          currency: string;
          payment_mode: string | null;
          budget_line: string | null;
          account_code: string | null;
          project_fund_class_code: string | null;
          donor_grant_source: string | null;
          budgeted: YesNo | null;
          procurement_required: YesNo | null;
          donor_restriction: YesNoUnsure | null;
          outstanding_advance: YesNo | null;
          finance_comments: string | null;
          budget_available: YesNo | null;
          director_comments: string | null;
          payment_voucher_number: string | null;
          qbo_posting_reference: string | null;
          payment_status: "pending" | "approved_for_payment" | "paid" | "posted_in_qbo" | "returned";
        }>;
        Relationships: [];
      };
      finance_approver_group: {
        Row: { requisition_id: string; user_id: string; added_by: string | null; created_at: string };
        Insert: { requisition_id: string; user_id: string; added_by?: string | null };
        Update: Partial<{ requisition_id: string; user_id: string }>;
        Relationships: [];
      };
      requisition_attachments: {
        Row: {
          id: string;
          requisition_id: string;
          uploaded_by: string;
          storage_path: string;
          file_name: string;
          file_size: number | null;
          section: FormSection;
          created_at: string;
        };
        Insert: {
          id?: string;
          requisition_id: string;
          uploaded_by: string;
          storage_path: string;
          file_name: string;
          file_size?: number | null;
          section?: FormSection;
        };
        Update: Partial<{ file_name: string }>;
        Relationships: [];
      };
      approval_actions: {
        Row: {
          id: string;
          requisition_id: string;
          stage_key: ApprovalStageKey;
          actor_id: string;
          decision: ApprovalDecision;
          comments: string | null;
          created_at: string;
        };
        Insert: never;
        Update: never;
        Relationships: [];
      };
      email_templates: {
        Row: { key: string; subject: string; html_body: string; updated_at: string };
        Insert: { key: string; subject: string; html_body: string };
        Update: Partial<{ subject: string; html_body: string }>;
        Relationships: [];
      };
      email_outbox: {
        Row: {
          id: string;
          requisition_id: string | null;
          template_key: string;
          to_emails: string[];
          cc_emails: string[];
          payload: Json;
          status: EmailStatus;
          attempts: number;
          error: string | null;
          created_at: string;
          sent_at: string | null;
        };
        Insert: never;
        Update: never;
        Relationships: [];
      };
      app_settings: {
        Row: { key: string; value: string; updated_at: string };
        Insert: { key: string; value: string };
        Update: Partial<{ value: string }>;
        Relationships: [];
      };
    };
    Views: Record<string, never>;
    Functions: {
      submit_requisition: { Args: { p_requisition_id: string; p_actor_id: string }; Returns: void };
      resubmit_requisition: { Args: { p_requisition_id: string; p_actor_id: string }; Returns: void };
      record_approval_action: {
        Args: {
          p_requisition_id: string;
          p_actor_id: string;
          p_decision: ApprovalDecision;
          p_comments?: string | null;
          p_return_to?: "requester" | "previous_stage";
          p_requires_reapproval?: boolean;
        };
        Returns: void;
      };
      complete_payment_processing: {
        Args: { p_requisition_id: string; p_actor_id: string; p_comments?: string | null };
        Returns: void;
      };
      get_eligible_approver_ids: { Args: { p_requisition_id: string; p_stage_key: ApprovalStageKey }; Returns: string[] };
      clear_must_change_password: { Args: Record<string, never>; Returns: void };
      enqueue_email: {
        Args: {
          p_requisition_id: string | null;
          p_template_key: string;
          p_to_emails: string[];
          p_payload?: Json;
          p_cc_emails?: string[];
        };
        Returns: string;
      };
    };
    Enums: {
      user_role: UserRole;
      approval_mode: ApprovalMode;
      approval_stage_key: ApprovalStageKey;
      approval_decision: ApprovalDecision;
      requisition_status: RequisitionStatus;
      yes_no: YesNo;
      yes_no_unsure: YesNoUnsure;
      email_status: EmailStatus;
      form_section: FormSection;
    };
  };
}
