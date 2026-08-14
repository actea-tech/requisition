import { randomUUID } from "node:crypto";
import { NextResponse, type NextRequest } from "next/server";
import { createClient } from "@/lib/supabase/server";
import type { Database } from "@/lib/supabase/database.types";

// Plain Route Handler (not a Server Action) so the client can drive the
// upload via XMLHttpRequest and get real byte-level progress — fetch/
// Server Actions don't expose upload progress events.
export async function POST(request: NextRequest) {
  const supabase = await createClient();
  const { data: userData } = await supabase.auth.getUser();
  if (!userData.user) return NextResponse.json({ error: "Not authenticated" }, { status: 401 });

  const formData = await request.formData();
  const file = formData.get("file") as File | null;
  const requisitionId = String(formData.get("requisitionId") ?? "");
  const section = String(formData.get("section") ?? "compliance_and_support");

  if (!file || file.size === 0 || !requisitionId) {
    return NextResponse.json({ error: "file and requisitionId are required" }, { status: 400 });
  }

  const storagePath = `${requisitionId}/${randomUUID()}-${file.name}`;
  const { error: uploadError } = await supabase.storage
    .from("requisition-attachments")
    .upload(storagePath, file, { contentType: file.type || undefined });

  if (uploadError) return NextResponse.json({ error: uploadError.message }, { status: 400 });

  const { data: attachment, error: insertError } = await supabase
    .from("requisition_attachments")
    .insert({
      requisition_id: requisitionId,
      uploaded_by: userData.user.id,
      storage_path: storagePath,
      file_name: file.name,
      file_size: file.size,
      section: section as Database["public"]["Tables"]["requisition_attachments"]["Row"]["section"],
    })
    .select("id, file_name, file_size, storage_path")
    .single();

  if (insertError) {
    await supabase.storage.from("requisition-attachments").remove([storagePath]);
    return NextResponse.json({ error: insertError.message }, { status: 400 });
  }

  return NextResponse.json({ attachment });
}
