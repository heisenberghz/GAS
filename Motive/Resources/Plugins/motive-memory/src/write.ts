import fs from "node:fs/promises";
import path from "node:path";
import { type MemoryRuntime, collectMemoryFiles, resolveWritablePath, touchIndex } from "./runtime";

type WriteArgs = {
  content: string;
  file?: string;
};

export async function runMemoryWrite(runtime: MemoryRuntime, args: WriteArgs): Promise<string> {
  const content = args.content?.trim();
  if (!content) {
    return "content is required";
  }

  let target: { absPath: string; relPath: string };
  try {
    target = resolveWritablePath(runtime, args.file);
  } catch (error) {
    return formatError(error);
  }

  try {
    await fs.mkdir(path.dirname(target.absPath), { recursive: true });
    let existing = "";
    try {
      existing = await fs.readFile(target.absPath, "utf8");
    } catch {
      existing = "";
    }
    const prefix = existing.length === 0 || existing.endsWith("\n") ? "" : "\n";
    const next = `${existing}${prefix}${content}\n`;
    await fs.writeFile(target.absPath, next, "utf8");
    const files = await collectMemoryFiles(runtime);
    await touchIndex(runtime, files.length);
    return `Written to ${target.relPath}`;
  } catch (error) {
    return `Failed to write memory: ${formatError(error)}`;
  }
}

function formatError(error: unknown): string {
  if (error instanceof Error) {
    return error.message;
  }
  return "Invalid write request.";
}
