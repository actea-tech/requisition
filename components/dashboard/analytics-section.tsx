import Link from "next/link";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { StatusBadge } from "@/components/requisitions/status-badge";
import { DepartmentSpendChart } from "@/components/dashboard/department-spend-chart";
import {
  ANALYTICS_RANGES,
  SCOPE_LABELS,
  formatDays,
  formatMoney,
  type DashboardAnalytics,
} from "@/lib/analytics";
import { STATUS_LABELS } from "@/lib/requisition-status";
import type { RequisitionStatus } from "@/lib/supabase/database.types";
import { cn } from "@/lib/utils";

function Stat({
  title,
  value,
  note,
  danger,
}: {
  title: string;
  value: string;
  note?: string;
  danger?: boolean;
}) {
  return (
    <Card>
      <CardHeader>
        <CardDescription>{title}</CardDescription>
        <CardTitle className={cn("text-3xl font-semibold tabular-nums", danger && "text-destructive")}>{value}</CardTitle>
        {note ? <p className="text-xs text-muted-foreground">{note}</p> : null}
      </CardHeader>
    </Card>
  );
}

function monthLabel(month: string) {
  return new Date(`${month}-01T00:00:00Z`).toLocaleString("en", { month: "short", timeZone: "UTC" });
}

export function AnalyticsSection({ data }: { data: DashboardAnalytics }) {
  const { counts, turnaround } = data;
  const stageMax = Math.max(1, ...data.by_stage.map((s) => s.count));
  const monthlyMax = Math.max(1, ...data.monthly.flatMap((m) => [m.submitted, m.completed]));
  const hasTurnaround = turnaround.sample > 0 && turnaround.average_days !== null;

  return (
    <section className="space-y-4" aria-labelledby="analytics-heading">
      <div className="flex flex-wrap items-end justify-between gap-3 border-t pt-6">
        <div>
          <h2 id="analytics-heading" className="text-xl font-semibold">
            Analytics
          </h2>
          <p className="text-sm text-muted-foreground">
            Showing: {SCOPE_LABELS[data.scope] ?? data.scope}. Drafts are not counted.
          </p>
        </div>
        <div className="flex gap-1 rounded-lg border p-1">
          {ANALYTICS_RANGES.map((r) => (
            <Link
              key={r.key}
              href={r.key === "all" ? "/" : `/?range=${r.key}`}
              className={cn(
                "rounded-md px-3 py-1 text-sm font-medium transition-colors",
                data.range === r.key ? "bg-primary text-primary-foreground" : "text-muted-foreground hover:bg-muted",
              )}
            >
              {r.label}
            </Link>
          ))}
        </div>
      </div>

      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <Stat title="Total requisitions" value={String(counts.total)} note="Submitted in this period" />
        <Stat title="In progress" value={String(counts.in_progress)} note="At a review or payment stage" />
        <Stat title="Completed (paid)" value={String(counts.completed)} note="Once paid, it counts as completed" />
        <Stat title="Returned for correction" value={String(counts.returned)} note="Waiting on the requester" />
        <Stat title="Rejected" value={String(counts.rejected)} />
        <Stat title="Cancelled" value={String(counts.cancelled)} />
        <Stat
          title="Average time to payment"
          value={hasTurnaround ? formatDays(turnaround.average_days) : "—"}
          note={
            hasTurnaround
              ? `Typical (median): ${formatDays(turnaround.median_days)}, from ${turnaround.sample} paid. Time spent returned or awaiting an invoice isn't counted.`
              : "No paid requisitions in this period yet."
          }
        />
        <Stat
          title="Overdue"
          value={String(data.overdue_count)}
          note={`More than ${data.overdue_days} days at one review or payment stage (right now)`}
          danger={data.overdue_count > 0}
        />
      </div>

      <div className="grid gap-4 lg:grid-cols-4">
        <Card className="lg:col-span-2">
          <CardHeader>
            <CardTitle className="text-base">Amount requisitioned</CardTitle>
            <CardDescription>
              Excludes rejected and cancelled. Product/Service requisitions count their estimate until the invoice is in.
            </CardDescription>
          </CardHeader>
          <CardContent>
            {data.amounts.length === 0 ? (
              <p className="text-sm text-muted-foreground">No requisitions in this period.</p>
            ) : (
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Currency</TableHead>
                    <TableHead className="text-right">Requisitioned</TableHead>
                    <TableHead className="text-right">Paid</TableHead>
                    <TableHead className="text-right">Still in the pipeline</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {data.amounts.map((a) => (
                    <TableRow key={a.currency}>
                      <TableCell className="font-medium">{a.currency}</TableCell>
                      <TableCell className="text-right tabular-nums">{formatMoney(a.requisitioned, a.currency)}</TableCell>
                      <TableCell className="text-right tabular-nums">{formatMoney(a.paid, a.currency)}</TableCell>
                      <TableCell className="text-right tabular-nums">{formatMoney(a.pipeline, a.currency)}</TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            )}
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle className="text-base">Fund requisitions awaiting accounting</CardTitle>
            <CardDescription>
              Paid out, but the requester hasn&apos;t accounted for the spend yet (right now).
            </CardDescription>
          </CardHeader>
          <CardContent className="space-y-1">
            <div className="text-3xl font-semibold tabular-nums">{data.awaiting_accounting.count}</div>
            {data.awaiting_accounting.amounts.map((a) => (
              <div key={a.currency} className="text-sm text-muted-foreground">
                {formatMoney(a.amount, a.currency)}
              </div>
            ))}
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle className="text-base">Consolidated payments</CardTitle>
            <CardDescription>
              Requisitions Finance combined into one payment. Their amounts are already counted above, so they are
              not added again.
            </CardDescription>
          </CardHeader>
          <CardContent className="space-y-1">
            <div className="text-3xl font-semibold tabular-nums">{data.consolidated?.count ?? 0}</div>
            {(data.consolidated?.amounts ?? []).map((a) => (
              <div key={a.currency} className="text-sm text-muted-foreground">
                {formatMoney(a.amount, a.currency)}
              </div>
            ))}
          </CardContent>
        </Card>
      </div>

      <div className="grid gap-4 lg:grid-cols-3">
        <Card>
          <CardHeader>
            <CardTitle className="text-base">Where requisitions are now</CardTitle>
            <CardDescription>Open requisitions by stage (right now).</CardDescription>
          </CardHeader>
          <CardContent>
            {data.by_stage.length === 0 ? (
              <p className="text-sm text-muted-foreground">Nothing is open right now.</p>
            ) : (
              <ul className="space-y-2.5">
                {data.by_stage.map((s) => (
                  <li key={s.status} className="space-y-1">
                    <div className="flex items-baseline justify-between gap-3 text-sm">
                      <span>{STATUS_LABELS[s.status as RequisitionStatus] ?? s.status}</span>
                      <span className="tabular-nums text-muted-foreground">{s.count}</span>
                    </div>
                    <div className="h-2 overflow-hidden rounded-full bg-muted">
                      <div
                        className="h-full rounded-full bg-chart-1"
                        style={{ width: `${Math.max(2, (s.count / stageMax) * 100)}%` }}
                      />
                    </div>
                  </li>
                ))}
              </ul>
            )}
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle className="text-base">Raised and paid, by month</CardTitle>
            <CardDescription>Last 12 months, whatever period is selected above.</CardDescription>
          </CardHeader>
          <CardContent className="space-y-3">
            <div
              className="flex h-40 items-end gap-1.5"
              role="img"
              aria-label="Requisitions submitted and paid per month over the last 12 months"
            >
              {data.monthly.map((m) => (
                <div
                  key={m.month}
                  className="flex h-full flex-1 flex-col justify-end gap-1"
                  title={`${monthLabel(m.month)} ${m.month.slice(0, 4)}: ${m.submitted} submitted, ${m.completed} paid`}
                >
                  <div className="flex flex-1 items-end justify-center gap-0.5">
                    <div
                      className="w-1/2 rounded-t bg-chart-1"
                      style={{ height: `${(m.submitted / monthlyMax) * 100}%`, minHeight: m.submitted ? 2 : 0 }}
                    />
                    <div
                      className="w-1/2 rounded-t bg-success"
                      style={{ height: `${(m.completed / monthlyMax) * 100}%`, minHeight: m.completed ? 2 : 0 }}
                    />
                  </div>
                  <div className="text-center text-[10px] text-muted-foreground">{monthLabel(m.month)}</div>
                </div>
              ))}
            </div>
            <div className="flex gap-4 text-xs text-muted-foreground">
              <span className="flex items-center gap-1.5">
                <span className="size-2.5 rounded-sm bg-chart-1" /> Submitted
              </span>
              <span className="flex items-center gap-1.5">
                <span className="size-2.5 rounded-sm bg-success" /> Paid
              </span>
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle className="text-base">Spend by department</CardTitle>
            <CardDescription>Top departments in this period, by amount requisitioned.</CardDescription>
          </CardHeader>
          <CardContent>
            <DepartmentSpendChart rows={data.by_department} />
          </CardContent>
        </Card>
      </div>

      <Card>
        <CardHeader>
          <CardTitle className="text-base">Open the longest</CardTitle>
          <CardDescription>
            The five requisitions that have been open longest since they were first submitted (right now).
          </CardDescription>
        </CardHeader>
        <CardContent>
          {data.oldest.length === 0 ? (
            <p className="text-sm text-muted-foreground">Nothing is open right now.</p>
          ) : (
            <div className="overflow-x-auto">
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Requisition</TableHead>
                    <TableHead>Requester</TableHead>
                    <TableHead>Stage</TableHead>
                    <TableHead className="text-right">Open for</TableHead>
                    <TableHead className="text-right">At this stage</TableHead>
                    <TableHead className="text-right">Amount</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {data.oldest.map((r) => {
                    const limit = r.status === "awaiting_invoice" ? data.invoice_overdue_days : data.overdue_days;
                    const stuck = r.status !== "returned" && r.days_in_stage > limit;
                    return (
                      <TableRow key={r.id}>
                        <TableCell>
                          <Link href={`/requisitions/${r.id}`} className="font-medium underline-offset-4 hover:underline">
                            {r.requisition_number ?? "Pending number"}
                          </Link>
                          {r.purpose ? (
                            <div className="max-w-xs truncate text-xs text-muted-foreground">{r.purpose}</div>
                          ) : null}
                        </TableCell>
                        <TableCell>
                          {r.requester_name ?? "—"}
                          {r.department_name ? (
                            <div className="text-xs text-muted-foreground">{r.department_name}</div>
                          ) : null}
                        </TableCell>
                        <TableCell>
                          <StatusBadge status={r.status as RequisitionStatus} />
                        </TableCell>
                        <TableCell className="text-right tabular-nums">{formatDays(r.age_days)}</TableCell>
                        <TableCell className={cn("text-right tabular-nums", stuck && "font-medium text-destructive")}>
                          {formatDays(r.days_in_stage)}
                        </TableCell>
                        <TableCell className="text-right tabular-nums">{formatMoney(r.amount, r.currency)}</TableCell>
                      </TableRow>
                    );
                  })}
                </TableBody>
              </Table>
            </div>
          )}
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2 text-base">
            Awaiting an invoice for too long
            {data.invoice_overdue.length > 0 ? <Badge variant="destructive">{data.invoice_overdue.length}</Badge> : null}
          </CardTitle>
          <CardDescription>
            Product/Service requisitions cleared for budget that have waited more than {data.invoice_overdue_days} days
            for the real invoice (right now).
          </CardDescription>
        </CardHeader>
        <CardContent>
          {data.invoice_overdue.length === 0 ? (
            <p className="text-sm text-muted-foreground">None. Nothing has been waiting too long.</p>
          ) : (
            <div className="overflow-x-auto">
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Requisition</TableHead>
                    <TableHead>Requester</TableHead>
                    <TableHead className="text-right">Waiting</TableHead>
                    <TableHead className="text-right">Estimate</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {data.invoice_overdue.map((r) => (
                    <TableRow key={r.id}>
                      <TableCell>
                        <Link href={`/requisitions/${r.id}`} className="font-medium underline-offset-4 hover:underline">
                          {r.requisition_number ?? "Pending number"}
                        </Link>
                        {r.purpose ? (
                          <div className="max-w-xs truncate text-xs text-muted-foreground">{r.purpose}</div>
                        ) : null}
                      </TableCell>
                      <TableCell>
                        {r.requester_name ?? "—"}
                        {r.department_name ? (
                          <div className="text-xs text-muted-foreground">{r.department_name}</div>
                        ) : null}
                      </TableCell>
                      <TableCell className="text-right tabular-nums text-destructive">
                        {formatDays(r.days_waiting)}
                      </TableCell>
                      <TableCell className="text-right tabular-nums">{formatMoney(r.amount, r.currency)}</TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </div>
          )}
        </CardContent>
      </Card>
    </section>
  );
}
