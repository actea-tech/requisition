import { createClient } from "@/lib/supabase/server";
import { CurrenciesPanel } from "@/components/settings/currencies-panel";

export default async function CurrenciesSettingsPage() {
  const supabase = await createClient();
  const { data } = await supabase.from("currencies").select("code").order("code");

  return <CurrenciesPanel currencies={(data ?? []).map((c) => c.code)} />;
}
