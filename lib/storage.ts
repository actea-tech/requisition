// Storage object keys are far stricter than filesystem filenames — an
// apostrophe, quote, or other punctuation in the original name can make
// the underlying object-storage backend reject the upload outright. Keep
// only a safe charset in the key itself; the original name is preserved
// separately (e.g. requisition_attachments.file_name) for display.
export function sanitizeFileNameForStorageKey(name: string): string {
  const sanitized = name.replace(/[^a-zA-Z0-9._-]+/g, "_");
  return sanitized || "file";
}
