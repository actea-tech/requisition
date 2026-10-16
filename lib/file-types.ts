import type { SupabaseClient } from "@supabase/supabase-js";
import type { Database } from "@/lib/supabase/database.types";

export interface FileTypeOption {
  /** Stored in the setting; also the primary extension. */
  id: string;
  label: string;
  extensions: string[];
}

// The file types an admin can switch on or off (Settings > Approval Rules).
export const FILE_TYPE_OPTIONS: FileTypeOption[] = [
  { id: "pdf", label: "PDF document", extensions: ["pdf"] },
  { id: "docx", label: "Word document", extensions: ["docx"] },
  { id: "doc", label: "Word document (older .doc format)", extensions: ["doc"] },
  { id: "xlsx", label: "Excel spreadsheet", extensions: ["xlsx"] },
  { id: "xls", label: "Excel spreadsheet (older .xls format)", extensions: ["xls"] },
  { id: "csv", label: "CSV file", extensions: ["csv"] },
  { id: "png", label: "PNG image", extensions: ["png"] },
  { id: "jpg", label: "JPEG image", extensions: ["jpg", "jpeg"] },
];

export const ALLOWED_FILE_TYPES_SETTING_KEY = "allowed_file_types";

// Finance's proposal; also what applies if the setting is missing or empty,
// so uploads are never left with nothing allowed.
export const DEFAULT_ALLOWED_FILE_TYPES = ["pdf"];

const KNOWN_IDS = new Set(FILE_TYPE_OPTIONS.map((o) => o.id));

export function parseAllowedFileTypes(value: string | null | undefined): string[] {
  const ids = (value ?? "")
    .split(",")
    .map((v) => v.trim().toLowerCase())
    .filter((v) => KNOWN_IDS.has(v));
  const unique = FILE_TYPE_OPTIONS.map((o) => o.id).filter((id) => ids.includes(id));
  return unique.length > 0 ? unique : DEFAULT_ALLOWED_FILE_TYPES;
}

export function serializeAllowedFileTypes(ids: string[]): string {
  return FILE_TYPE_OPTIONS.map((o) => o.id)
    .filter((id) => ids.includes(id))
    .join(",");
}

export function extensionsFor(ids: string[]): string[] {
  return FILE_TYPE_OPTIONS.filter((o) => ids.includes(o.id)).flatMap((o) => o.extensions);
}

/** For <input accept="…">, e.g. ".pdf,.docx". */
export function acceptAttribute(ids: string[]): string {
  return extensionsFor(ids)
    .map((e) => `.${e}`)
    .join(",");
}

/** For display, e.g. ".pdf, .docx". */
export function describeFileTypes(ids: string[]): string {
  return extensionsFor(ids)
    .map((e) => `.${e}`)
    .join(", ");
}

export function isFileTypeAllowed(fileName: string, ids: string[]): boolean {
  const dot = fileName.lastIndexOf(".");
  if (dot < 0) return false;
  return extensionsFor(ids).includes(fileName.slice(dot + 1).toLowerCase());
}

export function unsupportedFileMessage(fileName: string, ids: string[]): string {
  return `"${fileName}" can't be uploaded — supported file types: ${describeFileTypes(ids)}`;
}

export async function loadAllowedFileTypes(supabase: SupabaseClient<Database>): Promise<string[]> {
  const { data } = await supabase
    .from("app_settings")
    .select("value")
    .eq("key", ALLOWED_FILE_TYPES_SETTING_KEY)
    .maybeSingle();
  return parseAllowedFileTypes(data?.value);
}
