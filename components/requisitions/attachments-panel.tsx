"use client";

import { useRef, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { Paperclip, Trash2, Download } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Progress } from "@/components/ui/progress";
import { deleteAttachment, getAttachmentSignedUrl } from "@/app/(dashboard)/requisitions/[id]/actions";

export interface AttachmentRow {
  id: string;
  file_name: string;
  file_size: number | null;
  storage_path: string;
  uploaderName: string;
}

function formatSize(bytes: number | null) {
  if (!bytes) return "";
  if (bytes < 1024 * 1024) return `${Math.round(bytes / 1024)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

export function AttachmentsPanel({
  requisitionId,
  attachments,
  canUpload,
  canDelete,
}: {
  requisitionId: string;
  attachments: AttachmentRow[];
  canUpload: boolean;
  canDelete: boolean;
}) {
  const router = useRouter();
  const [isPending, startTransition] = useTransition();
  const [error, setError] = useState<string | null>(null);
  const [progress, setProgress] = useState<number | null>(null);
  const [uploadingName, setUploadingName] = useState<string | null>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);

  function handleFileChange(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    if (!file) return;

    setError(null);
    setProgress(0);
    setUploadingName(file.name);

    const formData = new FormData();
    formData.set("file", file);
    formData.set("requisitionId", requisitionId);
    formData.set("section", "compliance_and_support");

    const xhr = new XMLHttpRequest();
    xhr.open("POST", "/api/attachments");
    xhr.upload.onprogress = (e) => {
      if (e.lengthComputable) setProgress(Math.round((e.loaded / e.total) * 100));
    };
    xhr.onload = () => {
      setProgress(null);
      setUploadingName(null);
      if (fileInputRef.current) fileInputRef.current.value = "";
      if (xhr.status >= 200 && xhr.status < 300) {
        router.refresh();
      } else {
        try {
          setError(JSON.parse(xhr.responseText).error ?? "Upload failed.");
        } catch {
          setError("Upload failed.");
        }
      }
    };
    xhr.onerror = () => {
      setProgress(null);
      setUploadingName(null);
      setError("Upload failed — check your connection.");
    };
    xhr.send(formData);
  }

  async function handleView(path: string) {
    const url = await getAttachmentSignedUrl(path);
    if (url) window.open(url, "_blank", "noopener,noreferrer");
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-base">Supporting documents</CardTitle>
      </CardHeader>
      <CardContent className="space-y-3">
        {attachments.length === 0 ? (
          <p className="text-sm text-muted-foreground">No documents attached yet.</p>
        ) : (
          <ul className="space-y-1.5">
            {attachments.map((a) => (
              <li key={a.id} className="flex items-center justify-between rounded-md border px-3 py-2 text-sm">
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
              </li>
            ))}
          </ul>
        )}

        {canUpload ? (
          <div className="print:hidden">
            {progress !== null ? (
              <div className="space-y-1.5">
                <p className="truncate text-xs text-muted-foreground">Uploading {uploadingName}… {progress}%</p>
                <Progress value={progress} />
              </div>
            ) : (
              <input
                ref={fileInputRef}
                type="file"
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
