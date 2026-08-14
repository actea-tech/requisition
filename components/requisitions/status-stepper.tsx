import { Check, X } from "lucide-react";
import { STATUS_STEPS } from "@/lib/requisition-status";
import type { RequisitionStatus } from "@/lib/supabase/database.types";
import { cn } from "@/lib/utils";

export function StatusStepper({ status, returnedFromStage }: { status: RequisitionStatus; returnedFromStage: RequisitionStatus | null }) {
  const isTerminalBad = status === "returned" || status === "rejected";
  const effectiveStatus = isTerminalBad ? (returnedFromStage ?? "draft") : status;
  const currentIndex = STATUS_STEPS.findIndex((s) => s.status === effectiveStatus);

  return (
    <ol className="space-y-3">
      {STATUS_STEPS.map((step, index) => {
        const isDone = index < currentIndex || (index === currentIndex && !isTerminalBad && status === "paid_posted");
        const isCurrent = index === currentIndex;

        return (
          <li key={step.status} className="flex items-start gap-2.5">
            <span
              className={cn(
                "mt-0.5 flex size-5 shrink-0 items-center justify-center rounded-full text-[11px] font-semibold",
                isDone
                  ? "bg-success text-success-foreground"
                  : isCurrent
                    ? isTerminalBad
                      ? "bg-destructive text-destructive-foreground"
                      : "bg-primary text-primary-foreground"
                    : "bg-muted text-muted-foreground",
              )}
            >
              {isDone ? <Check className="size-3" /> : isCurrent && isTerminalBad ? <X className="size-3" /> : index + 1}
            </span>
            <span className={cn("text-sm", isCurrent ? "font-medium" : "text-muted-foreground")}>
              {step.label}
              {isCurrent && isTerminalBad ? (
                <span className="ml-1.5 text-xs text-destructive">
                  ({status === "rejected" ? "Rejected" : "Returned"})
                </span>
              ) : null}
            </span>
          </li>
        );
      })}
    </ol>
  );
}
