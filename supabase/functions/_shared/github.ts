/**
 * Small wrapper around GitHub REST API for issue creation.
 * Uses GITHUB_PAT (fine-grained, Issues:write on the target repo) from Supabase secrets.
 * Repo name comes from GITHUB_REPO env (e.g. "pdmedical/ai-outreach-frontend").
 */
const GITHUB_API = 'https://api.github.com';

export interface CreateIssueInput {
  title: string;
  body: string;
  labels?: string[];
}

export interface CreateIssueResult {
  number: number;
  html_url: string;
}

export async function createIssue(input: CreateIssueInput): Promise<CreateIssueResult> {
  const token = Deno.env.get('GITHUB_PAT');
  const repo = Deno.env.get('GITHUB_REPO');
  if (!token || !repo) {
    throw new Error('GITHUB_PAT and GITHUB_REPO must be set in Supabase secrets');
  }
  const resp = await fetch(`${GITHUB_API}/repos/${repo}/issues`, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${token}`,
      'Accept': 'application/vnd.github+json',
      'X-GitHub-Api-Version': '2022-11-28',
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      title: input.title,
      body: input.body,
      labels: input.labels ?? ['email-sync-bug', 'auto-reported'],
    }),
  });
  if (!resp.ok) {
    const text = await resp.text();
    throw new Error(`GitHub issue create failed (${resp.status}): ${text}`);
  }
  const json = await resp.json();
  return { number: json.number, html_url: json.html_url };
}
