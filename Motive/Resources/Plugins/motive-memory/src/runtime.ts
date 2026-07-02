import fs from "node:fs/promises";
import path from "node:path";

const MAX_SNIPPET_CHARS = 900;
const MAX_SEARCH_RESULTS = 8;

type SearchMatch = {
  relPath: string;
  absPath: string;
  score: number;
  startLine: number;
  endLine: number;
  snippet: string;
};

export type MemoryRuntime = {
  workspace: string;
  memoryDir: string;
  memoryFile: string;
  indexFile: string;
  rebuildMarker: string;
};

export async function prepareRuntime(directory: string): Promise<MemoryRuntime> {
  const workspace = resolveWorkspace(directory);
  const memoryDir = path.join(workspace, "memory");
  const memoryFile = path.join(workspace, "MEMORY.md");
  const indexFile = path.join(memoryDir, "index.sqlite");
  const rebuildMarker = path.join(memoryDir, ".rebuild");
  await fs.mkdir(memoryDir, { recursive: true });
  await ensureMemoryFile(memoryFile);
  await consumeRebuildMarker(rebuildMarker, indexFile);
  return { workspace, memoryDir, memoryFile, indexFile, rebuildMarker };
}

export async function collectMemoryFiles(runtime: MemoryRuntime): Promise<string[]> {
  const files: string[] = [];
  files.push(runtime.memoryFile);

  let memoryEntries: string[] = [];
  try {
    memoryEntries = await listMarkdownFiles(runtime.memoryDir);
  } catch {
    memoryEntries = [];
  }

  for (const file of memoryEntries) {
    const normalized = path.resolve(file);
    if (normalized !== path.resolve(runtime.memoryFile)) {
      files.push(normalized);
    }
  }
  return files;
}

export function formatSearchOutput(matches: SearchMatch[]): string {
  if (matches.length === 0) {
    return "No matching memories found.";
  }

  return matches
    .slice(0, MAX_SEARCH_RESULTS)
    .map((match) => {
      const score = Number.isFinite(match.score) ? match.score.toFixed(2) : "0.00";
      return `[${match.relPath}:${match.startLine}-${match.endLine}] (score: ${score})\n${match.snippet}`;
    })
    .join("\n\n");
}

export function computeMatches(content: string, relPath: string, absPath: string, query: string): SearchMatch | null {
  const cleanedQuery = query.trim().toLowerCase();
  if (!cleanedQuery) {
    return null;
  }

  const lines = content.split(/\r?\n/);
  const loweredLines = lines.map((line) => line.toLowerCase());
  const terms = tokenize(cleanedQuery);
  if (terms.length == 0) {
    return null;
  }

  let bestLine = -1;
  let bestScore = 0;
  for (let i = 0; i < loweredLines.length; i += 1) {
    const line = loweredLines[i];
    let termHits = 0;
    for (const term of terms) {
      if (line.includes(term)) {
        termHits += 1;
      }
    }
    let lineScore = termHits / terms.length;
    if (line.includes(cleanedQuery)) {
      lineScore += 0.35;
    }
    if (lineScore > bestScore) {
      bestScore = lineScore;
      bestLine = i;
    }
  }

  if (bestLine < 0 || bestScore <= 0) {
    return null;
  }

  const start = Math.max(0, bestLine - 3);
  const end = Math.min(lines.length - 1, bestLine + 6);
  const snippet = lines.slice(start, end + 1).join("\n").slice(0, MAX_SNIPPET_CHARS).trim();

  if (!snippet) {
    return null;
  }

  return {
    relPath,
    absPath,
    score: Math.min(bestScore, 1.0),
    startLine: start + 1,
    endLine: end + 1,
    snippet,
  };
}

export async function touchIndex(runtime: MemoryRuntime, fileCount: number): Promise<void> {
  const payload = JSON.stringify({
    version: 1,
    generatedAt: new Date().toISOString(),
    indexedFileCount: fileCount,
  });
  await fs.writeFile(runtime.indexFile, payload, "utf8");
}

export function resolveReadablePath(runtime: MemoryRuntime, requestedPath: string): string {
  const candidate = normalizeRelativePath(requestedPath);
  if (!candidate) {
    throw new Error("Path is required.");
  }

  if (candidate === "MEMORY.md") {
    return runtime.memoryFile;
  }

  if (!candidate.startsWith("memory/")) {
    throw new Error("Path must be MEMORY.md or inside memory/.");
  }
  if (!candidate.endsWith(".md")) {
    throw new Error("Only markdown files are readable.");
  }

  const abs = path.resolve(runtime.workspace, candidate);
  const memoryRoot = path.resolve(runtime.memoryDir);
  if (!abs.startsWith(memoryRoot + path.sep) && abs !== memoryRoot) {
    throw new Error("Path escapes memory directory.");
  }
  return abs;
}

export function resolveWritablePath(runtime: MemoryRuntime, requestedPath?: string): { absPath: string; relPath: string } {
  const normalized = normalizeRelativePath(requestedPath ?? "") || "MEMORY.md";
  if (normalized === "MEMORY.md") {
    return { absPath: runtime.memoryFile, relPath: "MEMORY.md" };
  }
  if (!normalized.startsWith("memory/")) {
    throw new Error("Writes are only allowed to MEMORY.md or memory/*.md");
  }
  if (!normalized.endsWith(".md")) {
    throw new Error("Writes must target markdown files.");
  }

  const absPath = path.resolve(runtime.workspace, normalized);
  const memoryRoot = path.resolve(runtime.memoryDir);
  if (!absPath.startsWith(memoryRoot + path.sep)) {
    throw new Error("Write target escapes memory directory.");
  }
  return { absPath, relPath: normalized };
}

export function toRelativePath(workspace: string, absPath: string): string {
  const rel = path.relative(workspace, absPath);
  return rel.split(path.sep).join("/");
}

function resolveWorkspace(directory: string): string {
  const configured = process.env.MOTIVE_WORKSPACE?.trim();
  if (configured) {
    return path.resolve(configured);
  }
  return path.resolve(directory);
}

async function ensureMemoryFile(memoryFile: string): Promise<void> {
  try {
    await fs.access(memoryFile);
  } catch {
    const initial = [
      "# MEMORY.md - Long-Term Memory",
      "",
      "_This file persists across sessions._",
      "",
      "## User Preferences",
      "",
      "## Key Facts",
      "",
      "## Patterns & Conventions",
      "",
    ].join("\n");
    await fs.writeFile(memoryFile, initial, "utf8");
  }
}

async function consumeRebuildMarker(markerPath: string, indexPath: string): Promise<void> {
  try {
    await fs.access(markerPath);
  } catch {
    return;
  }

  try {
    await fs.unlink(markerPath);
  } catch {
    // marker race is harmless
  }
  const payload = JSON.stringify({
    version: 1,
    rebuiltAt: new Date().toISOString(),
  });
  await fs.writeFile(indexPath, payload, "utf8");
}

async function listMarkdownFiles(root: string): Promise<string[]> {
  const out: string[] = [];
  const entries = await fs.readdir(root, { withFileTypes: true });
  for (const entry of entries) {
    if (entry.name.startsWith(".")) {
      continue;
    }
    const full = path.join(root, entry.name);
    if (entry.isDirectory()) {
      out.push(...(await listMarkdownFiles(full)));
      continue;
    }
    if (entry.isFile() && entry.name.toLowerCase().endsWith(".md")) {
      out.push(full);
    }
  }
  return out;
}

function tokenize(query: string): string[] {
  return query
    .split(/\s+/)
    .map((part) => part.trim())
    .filter((part) => part.length >= 2);
}

function normalizeRelativePath(input: string): string {
  return input.trim().replaceAll("\\", "/").replace(/^\.\/+/, "");
}
