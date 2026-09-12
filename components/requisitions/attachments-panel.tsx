"use client";

import { useRef, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { Paperclip, Trash2, Download } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Progress } from "@/components/ui/progress";
import { Textarea } from "@/components/ui/textarea";
import { deleteAttachment, getAttachmentSignedUrl } from "@/app/(dashboard)/requisitions/[id]/actions";
import type { FormSection } from "@/lib/supabase/database.types";

export interface AttachmentRow {
  id: string;
  file_name: string;
  file_size: number | null;
  storage_path: string;
  description: string | null;
  uploaderName: string;
}

function formatSize(bytes: number | null) {
  if (!bytes) return "";
  if (bytes < 1024 * 1024) return `${Math.round(bytes / 1024)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

function uploadOne(file: File, requisitionId: string, section: FormSection, description: string) {
  return new Promise<{ error: string | null }>((resolve) => {
    const formData = new FormData();
    formData.set("file", file);
    formData.set("requisitionId", requisitionId);
    formData.set("section", section);
    if (description) formData.set("description", description);

    const xhr = new XMLHttpRequest();
    xhr.open("POST", "/api/attachments");
    xhr.onload = () => {
      if (xhr.status >= 200 && xhr.status < 300) {
        resolve({ error: null });
      } else {
        try {
          resolve({ error: JSON.parse(xhr.responseText).error ?? "Upload failed." });
        } catch {
          resolve({ error: "Upload failed." });
        }
      }
    };
    xhr.onerror = () => resolve({ error: "Upload failed — check your connection." });
    xhr.send(formData);
  });
}

export function AttachmentsPanel({
  requisitionId,
  attachments,
  canUpload,
  canDelete,
  title = "Supporting documents",
  section = "compliance_and_support",
  withDescription = false,
}: {
  requisitionId: string;
  attachments: AttachmentRow[];
  canUpload: boolean;
  canDelete: boolean;
  title?: string;
  section?: FormSection;
  withDescription?: boolean;
}) {
  const router = useRouter();
  const [isPending, startTransition] = useTransition();
  const [error, setError] = useState<string | null>(null);
  const [description, setDescription] = useState("");
  const [uploading, setUploading] = useState<{ index: number; total: number; name: string } | null>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);

  async function handleFileChange(e: React.ChangeEvent<HTMLInputElement>) {
    const files = Array.from(e.target.files ?? []);
    if (files.length === 0) return;

    setError(null);
    for (let i = 0; i < files.length; i++) {
      setUploading({ index: i + 1, total: files.length, name: files[i].name });
      const { error: uploadError } = await uploadOne(files[i], requisitionId, section, description);
      if (uploadError) {
        setError(uploadError);
        break;
      }
    }
    setUploading(null);
    setDescription("");
    if (fileInputRef.current) fileInputRef.current.value = "";
    router.refresh();
  }

  async function handleView(path: string) {
    const url = await getAttachmentSignedUrl(path);
    if (url) window.open(url, "_blank", "noopener,noreferrer");
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-base">{title}</CardTitle>
      </CardHeader>
      <CardContent className="space-y-3">
        {attachments.length === 0 ? (
          <p className="text-sm text-muted-foreground">No documents attached yet.</p>
        ) : (
          <ul className="space-y-1.5">
            {attachments.map((a) => (
              <li key={a.id} className="rounded-md border px-3 py-2 text-sm">
                <div className="flex items-center justify-between">
                  <button
                    type="button"
                    onClick={() => handleView(a.storage_path)}
                    className="flex min-w-0 items-center gap-2 text-left hover:underline"
                  >
                    <Paperclip className="size-4 shrink-0 text-muted-foreground" />
                    <span className="truncate">{a.file_name}</span>
                    <span className="shrink-0 text-xs text-muted-foreground">{formatSize(a.file_size)}</span>
                  </button>
                  <div className="flex shrink-0 items-center gap-1">
                    <Button variant="ghost" size="icon-sm" onClick={() => handleView(a.storage_path)}>
                      <Download className="size-4" />
                    </Button>
                    {canDelete ? (
                      <Button
                        variant="ghost"
                        size="icon-sm"
                        onClick={() =>
                          startTransition(() => deleteAttachment(a.id, a.storage_path, requisitionId))
                        }
                      >
                        <Trash2 className="size-4" />
                      </Button>
                    ) : null}
                  </div>
                </div>
                {a.description ? <p className="mt-1 pl-6 text-xs text-muted-foreground">{a.description}</p> : null}
              </li>
            ))}
          </ul>
        )}

        {canUpload ? (
          <div className="space-y-2 print:hidden">
            {withDescription ? (
              <Textarea
                placeholder="Description of the document(s) being uploaded"
                value={description}
                onChange={(e) => setDescription(e.target.value)}
                disabled={uploading !== null}
                rows={2}
                className="text-sm"
              />
            ) : null}
            {uploading !== null ? (
              <div className="space-y-1.5">
                <p className="truncate text-xs text-muted-foreground">
                  Uploading {uploading.name} ({uploading.index}/{uploading.total})…
                </p>
                <Progress value={(uploading.index / uploading.total) * 100} />
              </div>
            ) : (
              <input
                ref={fileInputRef}
                type="file"
                multiple={withDescription}
                onChange={handleFileChange}
                disabled={isPending}
                className="text-sm file:mr-3 file:rounded-md file:border file:bg-secondary file:px-3 file:py-1.5 file:text-xs file:font-medium"
              />
            )}
            {error ? <p className="mt-1 text-sm text-destructive">{error}</p> : null}
          </div>
        ) : null}
      </CardContent>
    </Card>
  );
}
