// Host-organization helpers.
// Replaces hardcoded `@pdmedical.com.au` checks with registry-driven logic.
//
// Usage at the top of an Edge Function:
//   const hostDomains = await loadHostDomains(supabase);
//   if (isHostDomain(addr, hostDomains)) { ... }
//
// `hostDomains` is a Set<string> of lowercased domains. Pass it explicitly
// to keep helpers pure and easy to test.
//
// `loadHostDomains` accepts any Supabase client (typed as `unknown` to avoid
// version-pinning conflicts between callers that import different supabase-js
// versions).

interface SupabaseLike {
  from(table: string): {
    select(cols: string): {
      eq(col: string, val: unknown): Promise<{
        data: Array<{ domain: string }> | null;
        error: { message: string } | null;
      }>;
    };
  };
}

function domainOf(address: string | null | undefined): string {
  if (!address) return "";
  const at = address.lastIndexOf("@");
  if (at < 0) return "";
  return address.slice(at + 1).toLowerCase();
}

export function isHostDomain(
  address: string | null | undefined,
  hostDomains: Set<string>,
): boolean {
  const d = domainOf(address);
  if (!d) return false;
  return hostDomains.has(d);
}

export function classifyIsInternal(
  fromEmail: string | null | undefined,
  toEmails: (string | null | undefined)[] | null | undefined,
  ccEmails: (string | null | undefined)[] | null | undefined,
  bccEmails: (string | null | undefined)[] | null | undefined,
  hostDomains: Set<string>,
): boolean {
  const participants = [
    fromEmail,
    ...(toEmails ?? []),
    ...(ccEmails ?? []),
    ...(bccEmails ?? []),
  ].filter((p): p is string => typeof p === "string" && p.length > 0);

  if (participants.length === 0) return false; // safe default

  return participants.every((p) => isHostDomain(p, hostDomains));
}

export async function loadHostDomains(
  supabase: SupabaseLike | unknown,
): Promise<Set<string>> {
  const client = supabase as SupabaseLike;
  const { data, error } = await client
    .from("organizations")
    .select("domain")
    .eq("is_host", true);

  if (error) {
    console.error("loadHostDomains: failed to load registry", error);
    return new Set();
  }

  return new Set((data ?? []).map((r) => String(r.domain).toLowerCase()));
}
