// The options card's title applies to the single workout a single-file import
// produces (PLAN_IMPORT_SOURCES.md §2). Every source is single-entry except a
// ZIP, which the archive reader enumerates (Workouts::ArchiveReader): a bare
// track file, a gzip-compressed one and a KMZ all yield exactly one entry.
const MULTI_ENTRY_EXTENSION = ".zip";

export function singleImportFiles(files) {
  const list = Array.from(files ?? []);
  if (list.length !== 1) return false;

  const name = list[0]?.name?.toLowerCase() ?? "";
  return !name.endsWith(MULTI_ENTRY_EXTENSION);
}
