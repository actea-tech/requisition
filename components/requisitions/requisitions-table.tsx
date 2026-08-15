import Link from "next/link";
import { Download } from "lucide-react";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { StatusBadge } from "@/components/requisitions/status-badge";
import { Button } from "@/components/ui/button";
import type { RequisitionStatus } from "@/lib/supabase/database.types";

export interface RequisitionListRow {
  id: string;
  requisition_number: string | null;
  status: RequisitionStatus;
  purpose: string | null;
  amount: number | null;
  currency: string;
  created_at: string;
  requesterName: string;
  departmentName: string;
}

export function RequisitionsTable({ rows }: { rows: RequisitionListRow[] }) {
  if (rows.length === 0) {
    return <p className="text-sm text-muted-foreground">Nothing here yet.</p>;
  }

  return (
    <div className="overflow-x-auto rounded-lg border">
      <Table>
        <TableHeader>
          <TableRow>
            <TableHead>Requisition</TableHead>
            <TableHead>Requester</TableHead>
            <TableHead>Department</TableHead>
            <TableHead>Amount</TableHead>
            <TableHead>Status</TableHead>
            <TableHead>Date</TableHead>
            <TableHead className="w-10" />
          </TableRow>
        </TableHeader>
        <TableBody>
          {rows.map((row) => (
            <TableRow key={row.id} className="relative cursor-pointer transition-colors hover:bg-muted/50">
              <TableCell>
                {/* Stretched link: covers the whole row (position:relative
                    on TableRow), so clicking anywhere in the row navigates,
                    not just this cell's text. */}
                <Link href={`/requisitions/${row.id}`} className="absolute inset-0" aria-label={row.requisition_number ?? "Draft"} />
                <div className="font-medium">{row.requisition_number ?? "Draft"}</div>
                {row.purpose ? (
                  <div className="max-w-xs truncate text-xs text-muted-foreground">{row.purpose}</div>
                ) : null}
              </TableCell>
              <TableCell>{row.requesterName}</TableCell>
              <TableCell>{row.departmentName}</TableCell>
              <TableCell>{row.amount ? `${row.currency} ${row.amount.toLocaleString()}` : "—"}</TableCell>
              <TableCell>
                <StatusBadge status={row.status} />
              </TableCell>
              <TableCell>{new Date(row.created_at).toLocaleDateString()}</TableCell>
              <TableCell>
                {row.status === "paid_posted" || row.status === "rejected" ? (
                  <Button
                    variant="ghost"
                    size="icon-sm"
                    className="relative z-10"
                    title="Download PDF"
                    render={<a href={`/api/requisitions/${row.id}/pdf`} aria-label="Download PDF" />}
                    nativeButton={false}
                  >
                    <Download className="size-4" />
                  </Button>
                ) : null}
              </TableCell>
            </TableRow>
          ))}
        </TableBody>
      </Table>
    </div>
  );
}
