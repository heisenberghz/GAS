// Minimal Zod v4–compatible schema shim for OpenCode plugin runtime.
// OpenCode converts tool arg schemas via `schema._zod.def` and
// `schema._zod.toJSONSchema?.()`. We provide both so the built-in
// JSONSchemaGenerator never needs to recurse into real Zod internals.

interface ZodDef {
  type: string;
  typeName: string;
  innerType?: ZodLikeSchema;
  checks?: unknown[];
}

interface ZodInternals {
  def: ZodDef;
  toJSONSchema?: () => Record<string, unknown>;
  traits: Set<string>;
}

interface ZodLikeSchema {
  _zod: ZodInternals;
  optional(): ZodLikeSchema;
}

function zodString(): ZodLikeSchema {
  const schema: ZodLikeSchema = {
    _zod: {
      def: { type: "string", typeName: "ZodString", checks: [] },
      toJSONSchema: () => ({ type: "string" }),
      traits: new Set(["string"]),
    },
    optional() {
      return zodOptional(schema, { type: "string" });
    },
  };
  return schema;
}

function zodNumber(): ZodLikeSchema {
  const schema: ZodLikeSchema = {
    _zod: {
      def: { type: "number", typeName: "ZodNumber", checks: [] },
      toJSONSchema: () => ({ type: "number" }),
      traits: new Set(["number"]),
    },
    optional() {
      return zodOptional(schema, { type: "number" });
    },
  };
  return schema;
}

function zodOptional(
  innerType: ZodLikeSchema,
  jsonSchema: Record<string, unknown>,
): ZodLikeSchema {
  const schema: ZodLikeSchema = {
    _zod: {
      def: {
        type: "optional",
        typeName: "ZodOptional",
        innerType,
      },
      toJSONSchema: () => jsonSchema,
      traits: new Set(),
    },
    optional() {
      return this;
    },
  };
  return schema;
}

// ── Tool factory ────────────────────────────────────────────────────────

type ToolFactory = {
  <T>(definition: T): T;
  schema: {
    string: () => ZodLikeSchema;
    number: () => ZodLikeSchema;
  };
};

export type Plugin = (input: { directory: string }) => Promise<{
  tool: Record<string, unknown>;
}>;

export const tool: ToolFactory = Object.assign(
  <T>(definition: T): T => definition,
  {
    schema: {
      string: () => zodString(),
      number: () => zodNumber(),
    },
  },
);
