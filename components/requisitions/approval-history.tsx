import { format } from "date-fns";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import type { ApprovalDecision, ApprovalStageKey } from "@/lib/supabase/database.types";

const STAGE_LABELS: Record<ApprovalStageKey, string> = {
  department: "Department",
  finance: "Finance",
  director: "Director",
  payment: "Payment Processing",
};

const DECISION_LABELS: Record<ApprovalDecision, string> = {
  submitted: "Submitted",
  approved: "Approved",
  returned: "Returned",
  rejected: "Rejected",
  completed: "Completed",
};

const DECISION_VARIANT: Record<ApprovalDecision, "secondary" | "success" | "destructive" | "warning"> = {
  submitted: "secondary",
  approved: "success",
  returned: "warning",
  rejected: "destructive",
  completed: "success",
};

export interface HistoryEntry {
  id: string;
  stage_key: ApprovalStageKey;
  decision: ApprovalDecision;
  comments: string | null;
  created_at: string;
  actorName: string;
}

export function ApprovalHistory({ entries }: { entries: HistoryEntry[] }) {
  if (entries.length === 0) return null;

  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-base">Audit trail</CardTitle>
      </CardHeader>
      <CardContent>
        <ol className="space-y-4">
          {entries.map((entry) => (
            <li key={entry.id} className="flex gap-3 text-sm">
              <div className="w-32 shrink-0 text-xs text-muted-foreground">
                {format(new Date(entry.created_at), "d MMM yyyy, HH:mm")}
              </div>
              <div className="space-y-1">
                <div className="flex items-center gap-2">
                  <span className="font-medium">{entry.actorName}</span>
                  <Badge variant={DECISION_VARIANT[entry.decision]}>{DECISION_LABELS[entry.decision]}</Badge>
                  <span className="text-xs text-muted-foreground">at {STAGE_LABELS[entry.stage_key]}</span>
                </div>
                {entry.comments ? <p className="text-muted-foreground">{entry.comments}</p> : null}
              </div>
            </li>
          ))}
        </ol>
      </CardContent>
    </Card>
  );
}
