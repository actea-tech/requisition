import { randomUUID } from "node:crypto";
import { NextResponse, type NextRequest } from "next/server";
import { createClient } from "@/lib/supabase/server";
import type { Database } from "@/lib/supabase/database.types";

// Mirrors app/api/attachments/route.ts — a plain Route Handler (not a
// Server Action) so the client can drive the upload via XMLHttpRequest and
// get real byte-level progress. Each expenditure line carries its own
// description/amount alongside one attachment, rather than the shared
// description AttachmentsPanel uses for a batch.
export async function POST(request: NextRequest) {
  const supabase = await createClient();
  const { data: userData } = await supabase.auth.getUser();
  if (!userData.user) return NextResponse.json({ error: "Not authenticated" }, { status: 401 });

  const formData = await request.formData();
  const file = formData.get("file") as File | null;
  const requisitionId = String(formData.get("requisitionId") ?? "");
  const description = String(formData.get("description") ?? "").trim();
  const amount = Number(formData.get("amount"));
  const entryType = String(formData.get("entryType") ?? "expense");

  if (!requisitionId || !description || !amount || amount <= 0) {
    return NextResponse.json({ error: "requisitionId, description and a positive amount are required" }, { status: 400 });
  }

  let storagePath: string | null = null;
  if (file && file.size > 0) {
    storagePath = `${requisitionId}/expenditures/${randomUUID()}-${file.name}`;
    const { error: uploadError } = await supabase.storage
      .from("requisition-attachments")
      .upload(storagePath, file, { contentType: file.type || undefined });
    if (uploadError) return NextResponse.json({ error: uploadError.message }, { status: 400 });
  }

  const { data: expenditure, error: insertError } = await supabase
    .from("requisition_expenditures")
    .insert({
      requisition_id: requisitionId,
      created_by: userData.user.id,
      description,
      amount,
      entry_type: entryType as Database["public"]["Tables"]["requisition_expenditures"]["Row"]["entry_type"],
      storage_path: storagePath,
      file_name: file?.name ?? null,
      file_size: file?.size ?? null,
    })
    .select("id, description, amount, entry_type, storage_path, file_name, file_size")
    .single();

  if (insertError) {
    if (storagePath) await supabase.storage.from("requisition-attachments").remove([storagePath]);
    return NextResponse.json({ error: insertError.message }, { status: 400 });
  }

  return NextResponse.json({ expenditure });
}
