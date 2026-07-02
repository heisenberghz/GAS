import { tool, type Plugin } from "./tooling";
import { runMemorySearch } from "./search";
import { runMemoryGet } from "./get";
import { runMemoryWrite } from "./write";
import { prepareRuntime } from "./runtime";

const memoryPlugin: Plugin = async (input) => {
  return {
    tool: {
      memory_search: tool({
        description: "Semantic + keyword search across MEMORY.md and memory/*.md",
        args: {
          query: tool.schema.string(),
          maxResults: tool.schema.number().optional(),
          minScore: tool.schema.number().optional(),
        },
        async execute(args, context) {
          const runtime = await prepareRuntime(context.directory || input.directory);
          return runMemorySearch(runtime, args);
        },
      }),
      memory_get: tool({
        description: "Read specific memory file range from MEMORY.md or memory/*.md",
        args: {
          path: tool.schema.string(),
          from: tool.schema.number().optional(),
          lines: tool.schema.number().optional(),
        },
        async execute(args, context) {
          const runtime = await prepareRuntime(context.directory || input.directory);
          return runMemoryGet(runtime, args);
        },
      }),
      memory_write: tool({
        description: "Write memory content to MEMORY.md or memory/*.md",
        args: {
          content: tool.schema.string(),
          file: tool.schema.string().optional(),
        },
        async execute(args, context) {
          const runtime = await prepareRuntime(context.directory || input.directory);
          return runMemoryWrite(runtime, args);
        },
      }),
    },
  };
};

export default memoryPlugin;
