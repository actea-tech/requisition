import { Document, Page, Text, View, StyleSheet } from "@react-pdf/renderer";

const styles = StyleSheet.create({
  page: { padding: 36, fontSize: 10, fontFamily: "Helvetica", color: "#1a1a1a" },
  title: { fontSize: 16, fontWeight: 700, marginBottom: 2 },
  subtitle: { fontSize: 10, color: "#555", marginBottom: 16 },
  section: { marginBottom: 14 },
  sectionTitle: { fontSize: 11, fontWeight: 700, marginBottom: 6, borderBottom: "1 solid #ccc", paddingBottom: 3 },
  row: { flexDirection: "row", marginBottom: 4 },
  label: { width: 160, color: "#555" },
  value: { flex: 1, fontWeight: 500 },
  historyRow: { flexDirection: "row", borderBottom: "1 solid #eee", paddingVertical: 4 },
  historyStage: { width: 90 },
  historyDecision: { width: 80, textTransform: "capitalize" },
  historyActor: { width: 120 },
  historyDate: { width: 90 },
  historyComments: { flex: 1 },
  footer: { position: "absolute", bottom: 24, left: 36, right: 36, fontSize: 8, color: "#888", textAlign: "center" },
});

export interface RequisitionPdfData {
  requisition_number: string | null;
  requesterName: string;
  departmentName: string;
  purpose: string | null;
  activity_project: string | null;
  payee_name: string | null;
  payee_contact: string | null;
  amount: number | null;
  currency: string;
  payment_mode: string | null;
  payment_mode_details: string | null;
  budget_line: string | null;
  account_code: string | null;
  project_fund_class_code: string | null;
  donor_grant_source: string | null;
  payment_voucher_number: string | null;
  qbo_posting_reference: string | null;
  submitted_at: string | null;
  history: {
    stage_key: string;
    decision: string;
    comments: string | null;
    created_at: string;
    actorName: string;
  }[];
  generatedAt: string;
}

function Field({ label, value }: { label: string; value: string | number | null | undefined }) {
  return (
    <View style={styles.row}>
      <Text style={styles.label}>{label}</Text>
      <Text style={styles.value}>{value || value === 0 ? String(value) : "—"}</Text>
    </View>
  );
}

export function RequisitionPdfDocument({ data }: { data: RequisitionPdfData }) {
  return (
    <Document title={data.requisition_number ?? "Requisition"}>
      <Page size="A4" style={styles.page}>
        <Text style={styles.title}>{data.requisition_number ?? "Requisition"}</Text>
        <Text style={styles.subtitle}>Paid / Posted — {data.requesterName} · {data.departmentName}</Text>

        <View style={styles.section}>
          <Text style={styles.sectionTitle}>Request Details</Text>
          <Field label="Purpose" value={data.purpose} />
          <Field label="Activity / Project" value={data.activity_project} />
          <Field label="Submitted" value={data.submitted_at ? new Date(data.submitted_at).toLocaleDateString() : null} />
        </View>

        <View style={styles.section}>
          <Text style={styles.sectionTitle}>Payment Details</Text>
          <Field label="Payee" value={data.payee_name} />
          <Field label="Payee contact" value={data.payee_contact} />
          <Field label="Amount" value={data.amount != null ? `${data.currency} ${data.amount.toLocaleString()}` : null} />
          <Field label="Payment mode" value={data.payment_mode} />
          <Field label="Payment mode details" value={data.payment_mode_details} />
        </View>

        <View style={styles.section}>
          <Text style={styles.sectionTitle}>Budget and Coding</Text>
          <Field label="Budget line" value={data.budget_line} />
          <Field label="Account code" value={data.account_code} />
          <Field label="Project/Fund/Class code" value={data.project_fund_class_code} />
          <Field label="Donor/Grant source" value={data.donor_grant_source} />
        </View>

        <View style={styles.section}>
          <Text style={styles.sectionTitle}>Final Processing</Text>
          <Field label="Payment voucher number" value={data.payment_voucher_number} />
          <Field label="QBO posting reference" value={data.qbo_posting_reference} />
        </View>

        <View style={styles.section}>
          <Text style={styles.sectionTitle}>Approval History</Text>
          {data.history.map((h, i) => (
            <View key={i} style={styles.historyRow}>
              <Text style={styles.historyStage}>{h.stage_key}</Text>
              <Text style={styles.historyDecision}>{h.decision}</Text>
              <Text style={styles.historyActor}>{h.actorName}</Text>
              <Text style={styles.historyDate}>{new Date(h.created_at).toLocaleDateString()}</Text>
              <Text style={styles.historyComments}>{h.comments ?? ""}</Text>
            </View>
          ))}
        </View>

        <Text style={styles.footer}>Generated {new Date(data.generatedAt).toLocaleString()} · ACTEA Requisitions</Text>
      </Page>
    </Document>
  );
}
