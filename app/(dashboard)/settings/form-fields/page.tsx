import { createClient } from "@/lib/supabase/server";
import { FormFieldRow } from "@/components/settings/form-field-row";
import { Table, TableBody, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import type { FormSection } from "@/lib/supabase/database.types";

const SECTION_LABELS: Record<FormSection, string> = {
  request_details: "Request Details",
  payment_details: "Payment Details",
  budget_and_coding: "Budget and Coding",
  compliance_and_support: "Compliance and Support",
  finance_review: "Finance Review",
  final_processing: "Final Processing",
};

const SECTION_ORDER: FormSection[] = [
  "request_details",
  "payment_details",
  "budget_and_coding",
  "compliance_and_support",
  "finance_review",
  "final_processing",
];

export default async function FormFieldsSettingsPage() {
  const supabase = await createClient();
  const { data: fields } = await supabase
    .from("form_field_config")
    .select("id, section, label, help_text, is_visible, is_required, sort_order")
    .order("sort_order");

  return (
    <div className="space-y-8">
      <p className="text-sm text-muted-foreground">
        Request Details and Payment Details are the staff-facing basics and stay fixed. Budget and Coding /
        Compliance and Support appear on the staff form; Finance Review and Final Processing appear only to
        Finance at their respective stages. Turn a field off to hide it everywhere it would otherwise show.
      </p>

      {SECTION_ORDER.map((section) => {
        const sectionFields = (fields ?? []).filter((f) => f.section === section);
        if (sectionFields.length === 0) return null;

        return (
          <div key={section}>
            <h2 className="mb-2 text-sm font-semibold">{SECTION_LABELS[section]}</h2>
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Field</TableHead>
                  <TableHead className="w-24">Visible</TableHead>
                  <TableHead className="w-24">Required</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {sectionFields.map((field) => (
                  <FormFieldRow key={field.id} field={field} />
                ))}
              </TableBody>
            </Table>
          </div>
        );
      })}
    </div>
  );
}
