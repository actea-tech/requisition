"use client";

import { useState } from "react";
import { cn } from "@/lib/utils";
import { formatMoney, type DashboardAnalytics } from "@/lib/analytics";

const MAX_ROWS = 8;

export function DepartmentSpendChart({ rows }: { rows: DashboardAnalytics["by_department"] }) {
  // Amounts in different currencies can't be added or compared, so show one
  // currency at a time - the one with the most spend first.
  const currencies = Array.from(
    rows.reduce((totals, r) => totals.set(r.currency, (totals.get(r.currency) ?? 0) + r.total), new Map<string, number>()),
  )
    .sort((a, b) => b[1] - a[1])
    .map(([currency]) => currency);
  const [picked, setPicked] = useState<string | null>(null);
  const currency = picked && currencies.includes(picked) ? picked : (currencies[0] ?? "");

  const visible = rows.filter((r) => r.currency === currency).slice(0, MAX_ROWS);
  const max = Math.max(1, ...visible.map((r) => r.total));

  if (rows.length === 0) {
    return <p className="text-sm text-muted-foreground">No requisitions in this period.</p>;
  }

  return (
    <div className="space-y-3">
      {currencies.length > 1 ? (
        <div className="flex gap-1">
          {currencies.map((c) => (
            <button
              key={c}
              type="button"
              onClick={() => setPicked(c)}
              className={cn(
                "rounded-md border px-2.5 py-1 text-xs font-medium transition-colors",
                c === currency ? "border-primary bg-primary text-primary-foreground" : "text-muted-foreground hover:bg-muted",
              )}
            >
              {c}
            </button>
          ))}
        </div>
      ) : null}
      <ul className="space-y-2.5">
        {visible.map((r) => (
          <li key={r.department} className="space-y-1">
            <div className="flex items-baseline justify-between gap-3 text-sm">
              <span className="truncate">{r.department}</span>
              <span className="shrink-0 text-muted-foreground">
                {formatMoney(r.total, r.currency)} · {r.count}
              </span>
            </div>
            <div className="h-2 overflow-hidden rounded-full bg-muted">
              <div className="h-full rounded-full bg-chart-1" style={{ width: `${Math.max(2, (r.total / max) * 100)}%` }} />
            </div>
          </li>
        ))}
      </ul>
    </div>
  );
}
