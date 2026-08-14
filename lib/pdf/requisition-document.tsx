import { Document, Page, Text, View, Image, StyleSheet } from "@react-pdf/renderer";

const BRAND = {
  blue: "#1E49BA",
  red: "#E4302B",
  gold: "#F2A900",
  text: "#1F2430",
  muted: "#6B7280",
  border: "#E5E7EB",
  tint: "#F4F6FB",
  success: "#1C7C4B",
  successTint: "#E7F6EE",
};

const styles = StyleSheet.create({
  page: { padding: 0, fontSize: 10, fontFamily: "Helvetica", color: BRAND.text },
  content: { padding: 36, paddingTop: 20 },
  header: { flexDirection: "row", alignItems: "center", justifyContent: "space-between", marginBottom: 10 },
  brandRow: { flexDirection: "row", alignItems: "center", gap: 10 },
  logo: { width: 40, height: 40 },
  brandName: { fontSize: 18, fontWeight: 700, color: BRAND.blue, letterSpacing: 0.5 },
  brandSubtitle: { fontSize: 8, color: BRAND.muted, marginTop: 1 },
  headerRight: { alignItems: "flex-end" },
  reqNumber: { fontSize: 13, fontWeight: 700 },
  statusPill: {
    marginTop: 4,
    paddingVertical: 3,
    paddingHorizontal: 8,
    borderRadius: 3,
    backgroundColor: BRAND.successTint,
  },
  statusPillText: { fontSize: 8, fontWeight: 700, color: BRAND.success, letterSpacing: 0.5 },
  accentBar: { flexDirection: "row", height: 4, marginBottom: 18 },
  accentThird: { flex: 1 },
  subheading: { fontSize: 9, color: BRAND.muted, marginBottom: 16 },
  section: { marginBottom: 14 },
  sectionTitleRow: { flexDirection: "row", alignItems: "center", marginBottom: 6 },
  sectionTitleBar: { width: 3, height: 11, backgroundColor: BRAND.blue, marginRight: 6 },
  sectionTitle: { fontSize: 10.5, fontWeight: 700, color: BRAND.blue },
  sectionBody: {
    borderWidth: 1,
    borderColor: BRAND.border,
    borderRadius: 4,
    paddingVertical: 8,
    paddingHorizontal: 10,
  },
  row: { flexDirection: "row", marginBottom: 4 },
  label: { width: 160, color: BRAND.muted },
  value: { flex: 1, fontWeight: 500 },
  historyHeaderRow: {
    flexDirection: "row",
    backgroundColor: BRAND.tint,
    paddingVertical: 5,
    paddingHorizontal: 4,
    borderTopLeftRadius: 4,
    borderTopRightRadius: 4,
  },
  historyHeaderText: { fontSize: 8, fontWeight: 700, color: BRAND.muted, textTransform: "uppercase" },
  historyRow: { flexDirection: "row", borderBottom: "1 solid #eee", paddingVertical: 5, paddingHorizontal: 4 },
  historyStage: { width: 90, textTransform: "capitalize" },
  historyDecision: { width: 80, textTransform: "capitalize" },
  historyActor: { width: 120 },
  historyDate: { width: 90 },
  historyComments: { flex: 1 },
  footer: {
    position: "absolute",
    bottom: 0,
    left: 0,
    right: 0,
    paddingVertical: 10,
    paddingHorizontal: 36,
    borderTop: `1 solid ${BRAND.border}`,
    flexDirection: "row",
    justifyContent: "space-between",
  },
  footerText: { fontSize: 8, color: BRAND.muted },
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
}

function Field({ label, value }: { label: string; value: string | number | null | undefined }) {
  return (
    <View style={styles.row}>
      <Text style={styles.label}>{label}</Text>
      <Text style={styles.value}>{value || value === 0 ? String(value) : "—"}</Text>
    </View>
  );
}

function SectionTitle({ children }: { children: string }) {
  return (
    <View style={styles.sectionTitleRow}>
      <View style={styles.sectionTitleBar} />
      <Text style={styles.sectionTitle}>{children}</Text>
    </View>
  );
}

export function RequisitionPdfDocument({ data }: { data: RequisitionPdfData }) {
  return (
    <Document title={data.requisition_number ?? "Requisition"}>
      <Page size="A4" style={styles.page}>
        <View style={styles.content}>
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
              <View style={styles.statusPill}>
                <Text style={styles.statusPillText}>PAID / POSTED</Text>
              </View>
            </View>
          </View>

          <View style={styles.accentBar}>
            <View style={[styles.accentThird, { backgroundColor: BRAND.red }]} />
            <View style={[styles.accentThird, { backgroundColor: BRAND.gold }]} />
            <View style={[styles.accentThird, { backgroundColor: BRAND.blue }]} />
          </View>

          <Text style={styles.subheading}>{data.requesterName} · {data.departmentName}</Text>

          <View style={styles.section}>
            <SectionTitle>Request Details</SectionTitle>
            <View style={styles.sectionBody}>
              <Field label="Purpose" value={data.purpose} />
              <Field label="Activity / Project" value={data.activity_project} />
              <Field label="Submitted" value={data.submitted_at ? new Date(data.submitted_at).toLocaleDateString() : null} />
            </View>
          </View>

          <View style={styles.section}>
            <SectionTitle>Payment Details</SectionTitle>
            <View style={styles.sectionBody}>
              <Field label="Payee" value={data.payee_name} />
              <Field label="Payee contact" value={data.payee_contact} />
              <Field label="Amount" value={data.amount != null ? `${data.currency} ${data.amount.toLocaleString()}` : null} />
              <Field label="Payment mode" value={data.payment_mode} />
              <Field label="Payment mode details" value={data.payment_mode_details} />
            </View>
          </View>

          <View style={styles.section}>
            <SectionTitle>Budget and Coding</SectionTitle>
            <View style={styles.sectionBody}>
              <Field label="Budget line" value={data.budget_line} />
              <Field label="Account code" value={data.account_code} />
              <Field label="Project/Fund/Class code" value={data.project_fund_class_code} />
              <Field label="Donor/Grant source" value={data.donor_grant_source} />
            </View>
          </View>

          <View style={styles.section}>
            <SectionTitle>Final Processing</SectionTitle>
            <View style={styles.sectionBody}>
              <Field label="Payment voucher number" value={data.payment_voucher_number} />
              <Field label="QBO posting reference" value={data.qbo_posting_reference} />
            </View>
          </View>

          <View style={styles.section}>
            <SectionTitle>Approval History</SectionTitle>
            <View style={{ borderWidth: 1, borderColor: BRAND.border, borderRadius: 4, overflow: "hidden" }}>
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
            </View>
          </View>
        </View>

        <View style={styles.footer} fixed>
          <Text style={styles.footerText}>ACTEA Requisitions</Text>
          <Text style={styles.footerText}>Generated {new Date(data.generatedAt).toLocaleString()}</Text>
        </View>
      </Page>
    </Document>
  );
}
