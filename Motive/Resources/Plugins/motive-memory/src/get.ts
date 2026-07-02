import fs from "node:fs/promises";
import { resolveReadablePath, toRelativePath, type MemoryRuntime } from "./runtime";

type GetArgs = {
  path: string;
  from?: number;
  lines?: number;
};

export async function runMemoryGet(runtime: MemoryRuntime, args: GetArgs): Promise<string> {
  let absPath: string;
  try {
    absPath = resolveReadablePath(runtime, args.path);
  } catch (error) {
    return formatError(error);
  }

  let content = "";
  try {
    content = await fs.readFile(absPath, "utf8");
  } catch {
    return `File not found: ${args.path}`;
  }

  const allLines = content.split(/\r?\n/);
  const startLine = Math.max(1, Math.floor(args.from ?? 1));
  const lineCount = args.lines == nil ? allLines.length : Math.max(1, Math.floor(args.lines));
  const startIndex = Math.min(startLine - 1, Math.max(0, allLines.length - 1));
  const endExclusive = Math.min(allLines.length, startIndex + lineCount);
  const selected = allLines.slice(startIndex, endExclusive);
  const endLine = startIndex + selected.length;
  const relPath = toRelativePath(runtime.workspace, absPath);
  const body = selected.join("\n");
  return `[${relPath}:${startIndex + 1}-${endLine}]\n${body}`;
}

function formatError(error: unknown): string {
  if (error instanceof Error) {
    return error.message;
  }
  return "Invalid read request.";
}
