"use client";

import { useEffect, useState } from "react";
import { toast } from "sonner";
import { Download, Eye, Loader2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogTitle } from "@/components/ui/dialog";
import { getAttachmentDownloadUrl, getAttachmentSignedUrl } from "@/app/(dashboard)/requisitions/[id]/actions";
import {
  MAX_PREVIEW_BYTES,
  MAX_PREVIEW_COLUMNS,
  MAX_PREVIEW_ROWS,
  imageMimeType,
  previewKind,
} from "@/lib/document-preview";
import { cn } from "@/lib/utils";

export interface PreviewDoc {
  storagePath: string;
  fileName: string;
  /** Bytes, when known - lets a too-large file skip loading altogether. */
  fileSize?: number | null;
}

/** Saves the file to the computer. */
async function downloadDocument(doc: PreviewDoc) {
  const url = await getAttachmentDownloadUrl(doc.storagePath, doc.fileName);
  if (!url) {
    toast.error("Couldn't download that file.");
    return;
  }
  const link = document.createElement("a");
  link.href = url;
  link.download = doc.fileName;
  document.body.appendChild(link);
  link.click();
  link.remove();
}

/** The Preview (eye) button. */
export function PreviewButton({ onClick, label }: { onClick: () => void; label?: string }) {
  const text = label ?? "Preview";
  return (
    <Button variant="ghost" size="icon-sm" title={text} aria-label={text} onClick={onClick}>
      <Eye className="size-4" />
    </Button>
  );
}

/** The Download button. */
export function DownloadButton({ doc }: { doc: PreviewDoc }) {
  return (
    <Button
      variant="ghost"
      size="icon-sm"
      title="Download"
      aria-label={`Download ${doc.fileName}`}
      onClick={() => downloadDocument(doc)}
    >
      <Download className="size-4" />
    </Button>
  );
}

type Loaded =
  | { kind: "loading" }
  | { kind: "error"; message: string }
  | { kind: "too-large" }
  | { kind: "unsupported" }
  | { kind: "pdf"; blobUrl: string }
  | { kind: "image"; blobUrl: string }
  | { kind: "table"; sheets: { name: string; rows: string[][]; truncated: boolean }[] }
  | { kind: "docx"; html: string };

function cellText(value: unknown): string {
  if (value === null || value === undefined) return "";
  if (value instanceof Date) return value.toISOString().slice(0, 10);
  if (typeof value === "object") {
    const v = value as { result?: unknown; richText?: { text: string }[]; text?: unknown; hyperlink?: string };
    if (v.richText) return v.richText.map((r) => r.text).join("");
    if (v.result !== undefined) return cellText(v.result);
    if (v.text !== undefined) return cellText(v.text);
    return v.hyperlink ?? "";
  }
  return String(value);
}

async function loadDocument(doc: PreviewDoc, signal: AbortSignal): Promise<Loaded> {
  const kind = previewKind(doc.fileName);
  if (kind === "unsupported") return { kind: "unsupported" };
  if (doc.fileSize && doc.fileSize > MAX_PREVIEW_BYTES) return { kind: "too-large" };

  const url = await getAttachmentSignedUrl(doc.storagePath);
  if (!url) return { kind: "error", message: "Couldn't open that file." };

  const response = await fetch(url, { signal });
  if (!response.ok) return { kind: "error", message: "Couldn't load that file." };
  const length = Number(response.headers.get("content-length") ?? 0);
  if (length > MAX_PREVIEW_BYTES) return { kind: "too-large" };
  const buffer = await response.arrayBuffer();
  if (buffer.byteLength > MAX_PREVIEW_BYTES) return { kind: "too-large" };

  if (kind === "pdf") {
    return { kind: "pdf", blobUrl: URL.createObjectURL(new Blob([buffer], { type: "application/pdf" })) };
  }
  if (kind === "image") {
    return { kind: "image", blobUrl: URL.createObjectURL(new Blob([buffer], { type: imageMimeType(doc.fileName) })) };
  }

  if (kind === "csv") {
    const Papa = (await import("papaparse")).default;
    const parsed = Papa.parse<string[]>(new TextDecoder().decode(buffer), { skipEmptyLines: true });
    const all = parsed.data;
    return {
      kind: "table",
      sheets: [
        {
          name: "Data",
          rows: all.slice(0, MAX_PREVIEW_ROWS).map((r) => r.slice(0, MAX_PREVIEW_COLUMNS)),
          truncated: all.length > MAX_PREVIEW_ROWS,
        },
      ],
    };
  }

  if (kind === "xlsx") {
    const ExcelJS = (await import("exceljs")).default;
    const workbook = new ExcelJS.Workbook();
    await workbook.xlsx.load(buffer);
    const sheets = workbook.worksheets.map((sheet) => {
      const rows: string[][] = [];
      let truncated = false;
      sheet.eachRow({ includeEmpty: false }, (row) => {
        if (rows.length >= MAX_PREVIEW_ROWS) {
          truncated = true;
          return;
        }
        const cells: string[] = [];
        row.eachCell({ includeEmpty: true }, (cell, column) => {
          if (column > MAX_PREVIEW_COLUMNS) return;
          // A merged cell's text belongs to its first cell only, as in Excel.
          cells[column - 1] = cell.type === ExcelJS.ValueType.Merge ? "" : cellText(cell.value);
        });
        rows.push(Array.from(cells, (c) => c ?? ""));
      });
      return { name: sheet.name, rows, truncated };
    });
    return { kind: "table", sheets };
  }

  // docx: turned into HTML, then cleaned so nothing inside a document can run.
  const mammoth = await import("mammoth");
  const { value } = await mammoth.convertToHtml({ arrayBuffer: buffer });
  const DOMPurify = (await import("dompurify")).default;
  return { kind: "docx", html: DOMPurify.sanitize(value) };
}

function Message({ children }: { children: React.ReactNode }) {
  return <div className="flex h-full flex-col items-center justify-center gap-3 p-6 text-center text-muted-foreground">{children}</div>;
}

function TablePreview({ sheets }: { sheets: Extract<Loaded, { kind: "table" }>["sheets"] }) {
  const [active, setActive] = useState(0);
  const sheet = sheets[Math.min(active, sheets.length - 1)];
  if (!sheet) return <Message>This file has no data to show.</Message>;
  return (
    <div className="flex h-full flex-col">
      {sheets.length > 1 ? (
        <div className="flex shrink-0 gap-1 overflow-x-auto border-b p-2">
          {sheets.map((s, i) => (
            <button
              key={s.name + i}
              type="button"
              onClick={() => setActive(i)}
              className={cn(
                "shrink-0 rounded-md border px-2.5 py-1 text-xs font-medium transition-colors",
                i === active ? "border-primary bg-primary text-primary-foreground" : "text-muted-foreground hover:bg-muted",
              )}
            >
              {s.name}
            </button>
          ))}
        </div>
      ) : null}
      <div className="min-h-0 flex-1 overflow-auto">
        <table className="w-max min-w-full border-collapse text-xs">
          <tbody>
            {sheet.rows.map((row, r) => (
              <tr key={r} className={r === 0 ? "bg-muted/60 font-medium" : undefined}>
                {row.map((cell, c) => (
                  <td key={c} className="max-w-xs truncate border px-2 py-1" title={cell}>
                    {cell}
                  </td>
                ))}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      {sheet.truncated ? (
        <p className="shrink-0 border-t p-2 text-xs text-muted-foreground">
          Showing the first {MAX_PREVIEW_ROWS} rows. Download the file to see the rest.
        </p>
      ) : null}
    </div>
  );
}

/** The in-app viewer: opens a document in a window without downloading it. */
export function DocumentPreviewDialog({ doc, onClose }: { doc: PreviewDoc | null; onClose: () => void }) {
  const [loaded, setLoaded] = useState<Loaded>({ kind: "loading" });

  // Switching which document is open resets to "loading" during render (not in
  // the effect), so the effect below only reports results.
  const [shownKey, setShownKey] = useState<string | null>(null);
  const docKey = doc ? doc.storagePath : null;
  if (docKey !== shownKey) {
    setShownKey(docKey);
    setLoaded({ kind: "loading" });
  }

  useEffect(() => {
    if (!doc) return;
    const controller = new AbortController();
    let blobUrl: string | null = null;
    loadDocument(doc, controller.signal)
      .then((result) => {
        if (controller.signal.aborted) {
          if (result.kind === "pdf" || result.kind === "image") URL.revokeObjectURL(result.blobUrl);
          return;
        }
        if (result.kind === "pdf" || result.kind === "image") blobUrl = result.blobUrl;
        setLoaded(result);
      })
      .catch((error: unknown) => {
        if (controller.signal.aborted) return;
        console.error("Document preview failed", error);
        setLoaded({ kind: "error", message: "This file couldn't be previewed. You can still download it." });
      });
    return () => {
      controller.abort();
      if (blobUrl) URL.revokeObjectURL(blobUrl);
    };
    // The document is identified by its storage path.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [doc?.storagePath]);

  return (
    <Dialog open={doc !== null} onOpenChange={(open) => (open ? undefined : onClose())}>
      <DialogContent className="h-[85vh] grid-rows-[auto_minmax(0,1fr)] gap-0 p-0 sm:max-w-5xl">
        {doc ? (
          <>
            <div className="flex items-center justify-between gap-3 border-b py-2 pr-12 pl-4">
              <DialogTitle className="truncate text-sm font-medium">{doc.fileName}</DialogTitle>
              <Button variant="outline" size="sm" onClick={() => downloadDocument(doc)}>
                <Download className="size-4" /> Download
              </Button>
            </div>
            <div className="min-h-0 overflow-hidden">
              {loaded.kind === "loading" ? (
                <Message>
                  <Loader2 className="size-5 animate-spin" />
                  Loading preview…
                </Message>
              ) : loaded.kind === "error" ? (
                <Message>{loaded.message}</Message>
              ) : loaded.kind === "too-large" ? (
                <Message>
                  <p>This file is too large to preview ({Math.round(MAX_PREVIEW_BYTES / 1024 / 1024)} MB limit).</p>
                  <p className="text-xs">Use Download to open it on your computer.</p>
                </Message>
              ) : loaded.kind === "unsupported" ? (
                <Message>
                  <p>This file type can&apos;t be previewed here.</p>
                  <p className="text-xs">Use Download to open it on your computer.</p>
                </Message>
              ) : loaded.kind === "pdf" ? (
                <iframe src={`${loaded.blobUrl}#view=FitH`} title={doc.fileName} className="h-full w-full border-0" />
              ) : loaded.kind === "image" ? (
                // eslint-disable-next-line @next/next/no-img-element
                <img src={loaded.blobUrl} alt={doc.fileName} className="mx-auto h-full max-w-full object-contain p-2" />
              ) : loaded.kind === "table" ? (
                <TablePreview sheets={loaded.sheets} />
              ) : (
                <div
                  className="h-full overflow-auto p-6 text-sm leading-relaxed [&_h1]:mb-3 [&_h1]:text-xl [&_h1]:font-semibold [&_h2]:mb-2 [&_h2]:text-lg [&_h2]:font-semibold [&_h3]:mb-2 [&_h3]:font-semibold [&_li]:ml-5 [&_ol]:mb-3 [&_ol]:list-decimal [&_p]:mb-3 [&_table]:mb-3 [&_table]:border-collapse [&_td]:border [&_td]:px-2 [&_td]:py-1 [&_th]:border [&_th]:px-2 [&_th]:py-1 [&_ul]:mb-3 [&_ul]:list-disc"
                  // Sanitized with DOMPurify in loadDocument.
                  dangerouslySetInnerHTML={{ __html: loaded.html }}
                />
              )}
            </div>
          </>
        ) : null}
      </DialogContent>
    </Dialog>
  );
}
