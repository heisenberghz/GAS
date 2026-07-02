import fs from "node:fs/promises";
import { computeMatches, type MemoryRuntime, touchIndex, collectMemoryFiles, toRelativePath, formatSearchOutput } from "./runtime";

type SearchArgs = {
  query: string;
  maxResults?: number;
  minScore?: number;
};

export async function runMemorySearch(runtime: MemoryRuntime, args: SearchArgs): Promise<string> {
  const query = args.query?.trim() ?? "";
  if (!query) {
    return "Query is required.";
  }

  const files = await collectMemoryFiles(runtime);
  const matches = [];
  for (const absPath of files) {
    let content = "";
    try {
      content = await fs.readFile(absPath, "utf8");
    } catch {
      continue;
    }
    const relPath = toRelativePath(runtime.workspace, absPath);
    const match = computeMatches(content, relPath, absPath, query);
    if (match) {
      matches.push(match);
    }
  }

  matches.sort((lhs, rhs) => rhs.score - lhs.score);
  const minScore = typeof args.minScore === "number" ? args.minScore : 0;
  const filtered = matches.filter((item) => item.score >= minScore);
  const maxResults = Math.max(1, Math.min(args.maxResults ?? 5, 12));
  const finalMatches = filtered.slice(0, maxResults);

  await touchIndex(runtime, files.length);
  return formatSearchOutput(finalMatches);
}
