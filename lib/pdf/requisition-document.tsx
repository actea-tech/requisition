import type { ReactNode } from "react";
import { Document, Page, Text, View, Image, StyleSheet } from "@react-pdf/renderer";

const BRAND = {
  blue: "#1E49BA",
  red: "#E4302B",
  gold: "#F2A900",
  text: "#26303D",
  muted: "#8A93A3",
  border: "#EDEFF3",
  tint: "#F3F6FD",
  success: "#1C7C4B",
  successTint: "#E7F6EE",
  destructive: "#B3261E",
  destructiveTint: "#FBEAEA",
};

const styles = StyleSheet.create({
  page: { paddingTop: 72, paddingBottom: 60, paddingHorizontal: 72, fontSize: 9.5, fontFamily: "Helvetica", color: BRAND.text },
  header: { flexDirection: "row", alignItems: "flex-start", justifyContent: "space-between" },
  brandRow: { flexDirection: "row", alignItems: "center", gap: 9 },
  logo: { width: 30, height: 30 },
  brandName: { fontSize: 13, fontWeight: 700, color: BRAND.blue, letterSpacing: 0.3 },
  brandSubtitle: { fontSize: 7, color: BRAND.muted, marginTop: 1, textTransform: "uppercase", letterSpacing: 1 },
  headerRight: { alignItems: "flex-end" },
  reqNumber: { fontSize: 13, fontWeight: 700 },
  statusPill: { marginTop: 5, paddingVertical: 3, paddingHorizontal: 7, borderRadius: 3 },
  statusPillText: { fontSize: 7, fontWeight: 700, letterSpacing: 0.5 },
  accentBar: { flexDirection: "row", height: 1.25, marginTop: 16, marginBottom: 4 },
  accentThird: { flex: 1 },
  subheading: {
    fontSize: 8.5,
    color: BRAND.text,
    marginTop: 10,
    marginBottom: 22,
    paddingVertical: 6,
    paddingHorizontal: 9,
    backgroundColor: BRAND.tint,
    borderRadius: 3,
    borderLeft: `2 solid ${BRAND.blue}`,
    alignSelf: "flex-start",
  },
  section: { marginBottom: 18 },
  sectionTitle: {
    fontSize: 8.5,
    fontWeight: 700,
    color: BRAND.blue,
    textTransform: "uppercase",
    letterSpacing: 0.8,
    paddingBottom: 5,
    marginBottom: 8,
    borderBottom: `1 solid ${BRAND.border}`,
  },
  row: { flexDirection: "row", marginBottom: 7 },
  label: { width: 160, color: BRAND.muted },
  value: { flex: 1, fontWeight: 500 },
  historyHeaderRow: { flexDirection: "row", paddingBottom: 6, borderBottom: `1 solid ${BRAND.border}` },
  historyHeaderText: { fontSize: 8, fontWeight: 700, color: BRAND.text },
  historyRow: { flexDirection: "row", borderBottom: `1 solid ${BRAND.border}`, paddingVertical: 7 },
  historyStage: { width: 85, textTransform: "capitalize" },
  historyDecision: { width: 75, textTransform: "capitalize" },
  historyActor: { width: 115 },
  historyDate: { width: 80 },
  historyComments: { flex: 1 },
  footer: {
    position: "absolute",
    bottom: 28,
    left: 72,
    right: 72,
    paddingTop: 10,
    borderTop: `1 solid ${BRAND.border}`,
    flexDirection: "row",
    justifyContent: "space-between",
  },
  footerText: { fontSize: 7.5, color: BRAND.muted },
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
  logoSrc: string | null;
  status: "paid_posted" | "rejected";
}

function Field({ label, value }: { label: string; value: string | number | null | undefined }) {
  return (
    <View style={styles.row}>
      <Text style={styles.label}>{label}</Text>
      <Text style={styles.value}>{value || value === 0 ? String(value) : "—"}</Text>
    </View>
  );
}

function Section({ title, children }: { title: string; children: ReactNode }) {
  return (
    <View style={styles.section}>
      <Text style={styles.sectionTitle}>{title}</Text>
      {children}
    </View>
  );
}

export function RequisitionPdfDocument({ data }: { data: RequisitionPdfData }) {
  const isRejected = data.status === "rejected";
  return (
    <Document title={data.requisition_number ?? "Requisition"}>
      <Page size="A4" style={styles.page}>
        <View style={styles.header}>
          <View style={styles.brandRow}>
            {/* eslint-disable-next-line jsx-a11y/alt-text -- react-pdf's Image, not a DOM <img>; no alt prop exists */}
            {data.logoSrc ? <Image src={data.logoSrc} style={styles.logo} /> : null}
            <View>
              <Text style={styles.brandName}>ACTEA</Text>
              <Text style={styles.brandSubtitle}>Requisitions</Text>
            </View>
          </View>
          <View style={styles.headerRight}>
            <Text style={styles.reqNumber}>{data.requisition_number ?? "Requisition"}</Text>
            <View
              style={[
                styles.statusPill,
                { backgroundColor: isRejected ? BRAND.destructiveTint : BRAND.successTint },
              ]}
            >
              <Text style={[styles.statusPillText, { color: isRejected ? BRAND.destructive : BRAND.success }]}>
                {isRejected ? "Rejected" : "Paid / Posted"}
              </Text>
            </View>
          </View>
        </View>

        <View style={styles.accentBar}>
          <View style={[styles.accentThird, { backgroundColor: BRAND.red }]} />
          <View style={[styles.accentThird, { backgroundColor: BRAND.gold }]} />
          <View style={[styles.accentThird, { backgroundColor: BRAND.blue }]} />
        </View>

        <Text style={styles.subheading}>{data.requesterName} · {data.departmentName}</Text>

        <Section title="Request Details">
          <Field label="Purpose" value={data.purpose} />
          <Field label="Activity / Project" value={data.activity_project} />
          <Field label="Submitted" value={data.submitted_at ? new Date(data.submitted_at).toLocaleDateString() : null} />
        </Section>

        <Section title="Payment Details">
          <Field label="Payee" value={data.payee_name} />
          <Field label="Payee contact" value={data.payee_contact} />
          <Field label="Amount" value={data.amount != null ? `${data.currency} ${data.amount.toLocaleString()}` : null} />
          <Field label="Payment mode" value={data.payment_mode} />
          <Field label="Payment mode details" value={data.payment_mode_details} />
        </Section>

        <Section title="Budget and Coding">
          <Field label="Budget line" value={data.budget_line} />
          <Field label="Account code" value={data.account_code} />
          <Field label="Project/Fund/Class code" value={data.project_fund_class_code} />
          <Field label="Donor/Grant source" value={data.donor_grant_source} />
        </Section>

        {isRejected ? null : (
          <Section title="Final Processing">
            <Field label="Payment voucher number" value={data.payment_voucher_number} />
            <Field label="QBO posting reference" value={data.qbo_posting_reference} />
          </Section>
        )}

        <Section title="Approval History">
          <View style={styles.historyHeaderRow}>
            <Text style={[styles.historyHeaderText, styles.historyStage]}>Stage</Text>
            <Text style={[styles.historyHeaderText, styles.historyDecision]}>Decision</Text>
            <Text style={[styles.historyHeaderText, styles.historyActor]}>Actor</Text>
            <Text style={[styles.historyHeaderText, styles.historyDate]}>Date</Text>
            <Text style={[styles.historyHeaderText, styles.historyComments]}>Comments</Text>
          </View>
          {data.history.map((h, i) => (
            <View key={i} style={styles.historyRow}>
              <Text style={styles.historyStage}>{h.stage_key}</Text>
              <Text style={styles.historyDecision}>{h.decision}</Text>
              <Text style={styles.historyActor}>{h.actorName}</Text>
              <Text style={styles.historyDate}>{new Date(h.created_at).toLocaleDateString()}</Text>
              <Text style={styles.historyComments}>{h.comments ?? ""}</Text>
            </View>
          ))}
        </Section>

        <View style={styles.footer} fixed>
          <Text style={styles.footerText}>ACTEA Requisitions</Text>
          <Text style={styles.footerText}>Generated {new Date(data.generatedAt).toLocaleString()}</Text>
        </View>
      </Page>
    </Document>
  );
}
