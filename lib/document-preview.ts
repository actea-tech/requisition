// What the in-app document viewer can show, by file type. Everything else
// (older .doc/.xls, anything unknown) is download-only.

export type PreviewKind = "pdf" | "image" | "csv" | "xlsx" | "docx" | "unsupported";

/** Bigger files are not previewed (loading them into the page would be slow). */
export const MAX_PREVIEW_BYTES = 10 * 1024 * 1024;

/** Spreadsheets and CSVs show at most this much; the rest is in the download. */
export const MAX_PREVIEW_ROWS = 1000;
export const MAX_PREVIEW_COLUMNS = 50;

export function previewKind(fileName: string): PreviewKind {
  const ext = fileName.split(".").pop()?.toLowerCase() ?? "";
  if (ext === "pdf") return "pdf";
  if (ext === "png" || ext === "jpg" || ext === "jpeg") return "image";
  if (ext === "csv") return "csv";
  if (ext === "xlsx") return "xlsx";
  if (ext === "docx") return "docx";
  return "unsupported";
}

export function imageMimeType(fileName: string): string {
  return fileName.toLowerCase().endsWith(".png") ? "image/png" : "image/jpeg";
}

/** A readable file name from a storage path (".../<uuid>-<name>"). */
export function fileNameFromStoragePath(storagePath: string): string {
  const last = storagePath.split("/").pop() ?? storagePath;
  return last.replace(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}-/i, "");
}
