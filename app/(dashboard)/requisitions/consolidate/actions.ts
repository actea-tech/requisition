"use server";

import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { requireProfile } from "@/lib/auth/session";
import { canConsolidate } from "@/lib/roles";

// Combines the chosen requisitions (all at Payment Processing, one currency)
// into a new consolidated requisition and opens it. The database re-checks
// everything - who may do this, that they're all still ready to pay, that
// none is already combined - and works out the total.
export async function createConsolidatedRequisitionAction(requisitionIds: string[]) {
  const profile = await requireProfile();
  if (!canConsolidate(profile.role)) return { error: "Only Finance can combine requisitions." };

  const supabase = await createClient();
  const { data, error } = await supabase.rpc("create_consolidated_requisition", {
    p_requisition_ids: requisitionIds,
  });
  if (error || !data) return { error: error?.message ?? "Couldn't combine those requisitions." };

  redirect(`/requisitions/${data}`);
}
