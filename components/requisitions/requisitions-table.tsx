import Link from "next/link";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { StatusBadge } from "@/components/requisitions/status-badge";
import type { RequisitionStatus } from "@/lib/supabase/database.types";

export interface RequisitionListRow {
  id: string;
  requisition_number: string;
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
          </TableRow>
        </TableHeader>
        <TableBody>
          {rows.map((row) => (
            <TableRow key={row.id} className="cursor-pointer">
              <TableCell>
                <Link href={`/requisitions/${row.id}`} className="block">
                  <div className="font-medium">{row.requisition_number}</div>
                  {row.purpose ? (
                    <div className="max-w-xs truncate text-xs text-muted-foreground">{row.purpose}</div>
                  ) : null}
                </Link>
              </TableCell>
              <TableCell>
                <Link href={`/requisitions/${row.id}`}>{row.requesterName}</Link>
              </TableCell>
              <TableCell>
                <Link href={`/requisitions/${row.id}`}>{row.departmentName}</Link>
              </TableCell>
              <TableCell>
                <Link href={`/requisitions/${row.id}`}>
                  {row.amount ? `${row.currency} ${row.amount.toLocaleString()}` : "—"}
                </Link>
              </TableCell>
              <TableCell>
                <Link href={`/requisitions/${row.id}`}>
                  <StatusBadge status={row.status} />
                </Link>
              </TableCell>
              <TableCell>
                <Link href={`/requisitions/${row.id}`}>{new Date(row.created_at).toLocaleDateString()}</Link>
              </TableCell>
            </TableRow>
          ))}
        </TableBody>
      </Table>
    </div>
  );
}
