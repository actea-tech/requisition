-- Extensions
create extension if not exists pgcrypto;
create extension if not exists pg_net;

-- Enums
create type user_role as enum (
  'staff',
  'dept_head',
  'finance_accountant',
  'finance_reviewer',
  'director',
  'admin'
);

create type approval_mode as enum (
  'first_approver',
  'all_approvers',
  'quorum'
);

-- 'payment' is not an approval stage (no quorum/config) — it just tags the
-- audit-trail entry logged when Finance completes payment processing.
create type approval_stage_key as enum (
  'department',
  'finance',
  'director',
  'payment'
);

create type approval_decision as enum (
  'submitted',
  'approved',
  'returned',
  'rejected',
  'completed'
);

create type requisition_status as enum (
  'draft',
  'dept_review',
  'finance_review',
  'director_review',
  'approved_for_payment',
  'paid_posted',
  'returned',
  'rejected'
);

create type yes_no as enum ('yes', 'no');
create type yes_no_unsure as enum ('yes', 'no', 'not_sure');

create type email_status as enum ('pending', 'sent', 'failed');

create type form_section as enum (
  'request_details',
  'payment_details',
  'budget_and_coding',
  'compliance_and_support',
  'finance_review',
  'final_processing'
);
