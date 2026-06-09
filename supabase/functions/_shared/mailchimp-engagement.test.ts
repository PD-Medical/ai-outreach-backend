import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  applyMailchimpScoreToState,
  buildMailchimpEngagementExternalId,
  createEmptyMailchimpScoringState,
  mailchimpEngagementScheduleRateToCron,
  mapMailchimpActivity,
  resolveMailchimpContactBatch,
  scoreMailchimpActivity,
  syncMailchimpEngagementForNewsletters,
} from "./mailchimp-engagement.ts";

Deno.test("mailchimpEngagementScheduleRateToCron maps supported rates", () => {
  assertEquals(mailchimpEngagementScheduleRateToCron("15 minutes"), "*/15 * * * *");
  assertEquals(mailchimpEngagementScheduleRateToCron("30 minutes"), "*/30 * * * *");
  assertEquals(mailchimpEngagementScheduleRateToCron("1 hour"), "0 * * * *");
  assertEquals(mailchimpEngagementScheduleRateToCron("2 hours"), "0 */2 * * *");
  assertEquals(mailchimpEngagementScheduleRateToCron("6 hours"), "0 */6 * * *");
  assertEquals(mailchimpEngagementScheduleRateToCron("unexpected"), "0 * * * *");
});

Deno.test("mapMailchimpActivity maps report actions to local event types", () => {
  assertEquals(mapMailchimpActivity({ action: "open", timestamp: "2026-06-09T00:00:00Z" })?.eventType, "opened");
  assertEquals(mapMailchimpActivity({ action: "click", timestamp: "2026-06-09T00:00:00Z", url: "https://example.com" })?.eventType, "clicked");
  assertEquals(mapMailchimpActivity({ action: "hard_bounce", timestamp: "2026-06-09T00:00:00Z" })?.eventType, "bounced");
  assertEquals(mapMailchimpActivity({ action: "unsub", timestamp: "2026-06-09T00:00:00Z" })?.eventType, "complained");
  assertEquals(mapMailchimpActivity({ action: "abuse", timestamp: "2026-06-09T00:00:00Z" })?.eventType, "complained");
  assertEquals(mapMailchimpActivity({ action: "unknown", timestamp: "2026-06-09T00:00:00Z" }), null);
});

Deno.test("mapMailchimpActivity requires stable activity timestamps", () => {
  assertEquals(mapMailchimpActivity({ action: "open" }), null);
  assertEquals(mapMailchimpActivity({ action: "open", timestamp: "not-a-date" }), null);
  assertEquals(
    mapMailchimpActivity({ action: "open", created_at: "2026-06-09T00:00:00Z" })?.timestamp,
    "2026-06-09T00:00:00.000Z",
  );
});

Deno.test("scoreMailchimpActivity scores first open once", () => {
  const state = createEmptyMailchimpScoringState();
  const first = mapMailchimpActivity({ action: "open", timestamp: "2026-06-09T00:00:00Z" })!;
  const firstScore = scoreMailchimpActivity(first, state);
  assertEquals(firstScore.score, 2);
  applyMailchimpScoreToState(first, firstScore.score, state);

  const second = mapMailchimpActivity({ action: "open", timestamp: "2026-06-09T00:01:00Z" })!;
  assertEquals(scoreMailchimpActivity(second, state).score, 0);
});

Deno.test("scoreMailchimpActivity scores unique clicks and caps at 12", () => {
  const state = createEmptyMailchimpScoringState();
  const clickA = mapMailchimpActivity({ action: "click", timestamp: "2026-06-09T00:00:00Z", url: "https://example.com/a" })!;
  const scoreA = scoreMailchimpActivity(clickA, state);
  assertEquals(scoreA.score, 8);
  applyMailchimpScoreToState(clickA, scoreA.score, state);

  const clickARepeat = mapMailchimpActivity({ action: "click", timestamp: "2026-06-09T00:01:00Z", url: "https://example.com/a" })!;
  assertEquals(scoreMailchimpActivity(clickARepeat, state).score, 0);

  const clickB = mapMailchimpActivity({ action: "click", timestamp: "2026-06-09T00:02:00Z", url: "https://example.com/b" })!;
  const scoreB = scoreMailchimpActivity(clickB, state);
  assertEquals(scoreB.score, 2);
  applyMailchimpScoreToState(clickB, scoreB.score, state);

  const clickC = mapMailchimpActivity({ action: "click", timestamp: "2026-06-09T00:03:00Z", url: "https://example.com/c" })!;
  const scoreC = scoreMailchimpActivity(clickC, state);
  assertEquals(scoreC.score, 2);
  applyMailchimpScoreToState(clickC, scoreC.score, state);

  const clickD = mapMailchimpActivity({ action: "click", timestamp: "2026-06-09T00:04:00Z", url: "https://example.com/d" })!;
  assertEquals(scoreMailchimpActivity(clickD, state).score, 0);
});

Deno.test("scoreMailchimpActivity scores negative actions once", () => {
  const state = createEmptyMailchimpScoringState();
  const bounce = mapMailchimpActivity({ action: "bounce", timestamp: "2026-06-09T00:00:00Z" })!;
  const bounceScore = scoreMailchimpActivity(bounce, state);
  assertEquals(bounceScore.score, -10);
  applyMailchimpScoreToState(bounce, bounceScore.score, state);
  assertEquals(scoreMailchimpActivity(bounce, state).score, 0);

  const unsub = mapMailchimpActivity({ action: "unsub", timestamp: "2026-06-09T00:00:00Z" })!;
  assertEquals(scoreMailchimpActivity(unsub, state).score, -20);

  const abuse = mapMailchimpActivity({ action: "abuse", timestamp: "2026-06-09T00:00:00Z" })!;
  assertEquals(scoreMailchimpActivity(abuse, state).score, -30);
});

Deno.test("buildMailchimpEngagementExternalId is deterministic and normalizes email", async () => {
  const first = await buildMailchimpEngagementExternalId({
    campaignId: "abc123",
    email: " Person@Example.COM ",
    emailId: null,
    action: "click",
    timestamp: "2026-06-09T00:00:00.000Z",
    url: "https://example.com/a?x=1",
  });
  const second = await buildMailchimpEngagementExternalId({
    campaignId: "abc123",
    email: "person@example.com",
    emailId: null,
    action: "click",
    timestamp: "2026-06-09T00:00:00.000Z",
    url: "https://example.com/a?x=1",
  });

  assertEquals(first, second);
  assertEquals(first, "mailchimp:abc123:person%40example.com:click:2026-06-09T00%3A00%3A00.000Z:https%3A%2F%2Fexample.com%2Fa%3Fx%3D1");
});

Deno.test("buildMailchimpEngagementExternalId does not depend on array index for open events", async () => {
  const first = await buildMailchimpEngagementExternalId({
    campaignId: "abc123",
    email: "person@example.com",
    emailId: "subscriber-hash",
    action: "open",
    timestamp: "2026-06-09T00:00:00.000Z",
    activity: { action: "open", timestamp: "2026-06-09T00:00:00.000Z", ip: "127.0.0.1" },
  });
  const second = await buildMailchimpEngagementExternalId({
    campaignId: "abc123",
    email: "person@example.com",
    emailId: "subscriber-hash",
    action: "open",
    timestamp: "2026-06-09T00:00:00.000Z",
    activity: { timestamp: "2026-06-09T00:00:00.000Z", ip: "127.0.0.1", action: "open" },
  });
  const later = await buildMailchimpEngagementExternalId({
    campaignId: "abc123",
    email: "person@example.com",
    emailId: "subscriber-hash",
    action: "open",
    timestamp: "2026-06-09T00:01:00.000Z",
    activity: { action: "open", timestamp: "2026-06-09T00:01:00.000Z", ip: "127.0.0.1" },
  });

  assertEquals(first, second);
  assertEquals(first === later, false);
});

Deno.test("resolveMailchimpContactBatch prefers Mailchimp links over contact fallback", async () => {
  const calls: Array<{ table: string; emails: string[] }> = [];
  const supabase = {
    from(table: string) {
      const state: { listId?: string; emails: string[] } = { emails: [] };
      return {
        select() {
          return this;
        },
        eq(_column: string, value: string) {
          state.listId = value;
          return this;
        },
        in(_column: string, values: string[]) {
          calls.push({ table, emails: values });
          if (table === "mailchimp_contact_links") {
            return {
              data: state.listId === "list-a"
                ? [{ contact_id: "linked-contact", email_address: "linked@example.com" }]
                : [],
              error: null,
            };
          }
          return {
            data: [{ id: "fallback-contact", email: "fallback@example.com" }],
            error: null,
          };
        },
      };
    },
  };

  const resolved = await resolveMailchimpContactBatch(supabase as any, [
    { listId: "list-a", email: "linked@example.com" },
    { listId: "list-a", email: "fallback@example.com" },
  ]);

  assertEquals(resolved.resolve({ listId: "list-a", email: "linked@example.com" }), "linked-contact");
  assertEquals(resolved.resolve({ listId: "list-a", email: "fallback@example.com" }), "fallback-contact");
  assertEquals(calls[0], { table: "mailchimp_contact_links", emails: ["linked@example.com", "fallback@example.com"] });
  assertEquals(calls[1], { table: "contacts", emails: ["linked@example.com", "fallback@example.com"] });
});

Deno.test("resolveMailchimpContactBatch keeps Mailchimp list matches separate for the same email", async () => {
  const supabase = {
    from(table: string) {
      const state: { listId?: string } = {};
      return {
        select() {
          return this;
        },
        eq(_column: string, value: string) {
          state.listId = value;
          return this;
        },
        in(_column: string, values: string[]) {
          if (table === "mailchimp_contact_links") {
            return {
              data: values.includes("shared@example.com")
                ? [{ contact_id: `linked-${state.listId}`, email_address: "shared@example.com" }]
                : [],
              error: null,
            };
          }
          return {
            data: [{ id: "fallback-contact", email: "shared@example.com" }],
            error: null,
          };
        },
      };
    },
  };

  const resolved = await resolveMailchimpContactBatch(supabase as any, [
    { listId: "list-a", email: "shared@example.com" },
    { listId: "list-b", email: "shared@example.com" },
  ]);

  assertEquals(resolved.resolve({ listId: "list-a", email: "shared@example.com" }), "linked-list-a");
  assertEquals(resolved.resolve({ listId: "list-b", email: "shared@example.com" }), "linked-list-b");
  assertEquals(resolved.resolve({ listId: null, email: "shared@example.com" }), "fallback-contact");
});

Deno.test("syncMailchimpEngagementForNewsletters dry-run polls without campaign bridge", async () => {
  const writeTables: string[] = [];
  const supabase = {
    from(table: string) {
      return {
        select() {
          return this;
        },
        eq() {
          return this;
        },
        in(_column: string, values: string[]) {
          if (table === "mailchimp_contact_links") {
            return { data: [], error: null };
          }
          if (table === "contacts") {
            return {
              data: values.includes("person@example.com")
                ? [{ id: "contact-1", email: "person@example.com" }]
                : [],
              error: null,
            };
          }
          return { data: [], error: null };
        },
        maybeSingle() {
          return { data: null, error: null };
        },
        insert() {
          writeTables.push(table);
          throw new Error(`unexpected insert into ${table}`);
        },
        update() {
          writeTables.push(table);
          throw new Error(`unexpected update to ${table}`);
        },
      };
    },
  };

  const stats = await syncMailchimpEngagementForNewsletters(
    supabase as any,
    [{
      id: "newsletter-1",
      mailchimp_campaign_id: "mailchimp-campaign-1",
      campaign_id: null,
      subject: "Dry run campaign",
      audience_id: "list-a",
    }],
    {
      dryRun: true,
      maxEmailsPerCampaign: 1,
      fetchEmailActivityPage: async (campaignId, count, offset) => {
        assertEquals(campaignId, "mailchimp-campaign-1");
        assertEquals(count, 1);
        assertEquals(offset, 0);
        return {
          emails: [{
            email_id: "subscriber-hash",
            email_address: "person@example.com",
            list_id: "list-a",
            activity: [{ action: "open", timestamp: "2026-06-09T00:00:00Z" }],
          }],
        };
      },
    },
  );

  assertEquals(stats.campaigns_scanned, 1);
  assertEquals(stats.activities_scanned, 1);
  assertEquals(stats.events_inserted, 1);
  assertEquals(stats.events_skipped_existing, 0);
  assertEquals(stats.contacts_matched, 1);
  assertEquals(stats.contacts_missing, 0);
  assertEquals(stats.summaries_updated, 0);
  assertEquals(stats.errors, []);
  assertEquals(writeTables, []);
});

Deno.test("syncMailchimpEngagementForNewsletters records real writes through atomic RPC", async () => {
  const rpcCalls: Array<{ name: string; args: Record<string, unknown> }> = [];
  const supabase = {
    from(table: string) {
      return {
        select() {
          return this;
        },
        eq() {
          return this;
        },
        in(_column: string, values: string[]) {
          if (table === "mailchimp_contact_links") {
            return { data: [], error: null };
          }
          if (table === "contacts") {
            return {
              data: values.includes("person@example.com")
                ? [{ id: "contact-1", email: "person@example.com" }]
                : [],
              error: null,
            };
          }
          return { data: [], error: null };
        },
      };
    },
    rpc(name: string, args: Record<string, unknown>) {
      rpcCalls.push({ name, args });
      return { data: [{ status: "inserted" }], error: null };
    },
  };

  const stats = await syncMailchimpEngagementForNewsletters(
    supabase as any,
    [{
      id: "newsletter-1",
      mailchimp_campaign_id: "mailchimp-campaign-1",
      campaign_id: "11111111-1111-1111-1111-111111111111",
      subject: "Real run campaign",
      audience_id: "list-a",
    }],
    {
      maxEmailsPerCampaign: 1,
      fetchEmailActivityPage: async () => ({
        emails: [{
          email_id: "subscriber-hash",
          email_address: "person@example.com",
          list_id: "list-a",
          activity: [{ action: "open", timestamp: "2026-06-09T00:00:00Z" }],
        }],
      }),
    },
  );

  assertEquals(stats.events_inserted, 1);
  assertEquals(stats.events_skipped_existing, 0);
  assertEquals(stats.summaries_updated, 1);
  assertEquals(rpcCalls.length, 1);
  assertEquals(rpcCalls[0].name, "record_mailchimp_campaign_event");
  assertEquals(rpcCalls[0].args.p_campaign_id, "11111111-1111-1111-1111-111111111111");
  assertEquals(rpcCalls[0].args.p_contact_id, "contact-1");
  assertEquals(rpcCalls[0].args.p_event_type, "opened");
  assertEquals(rpcCalls[0].args.p_is_unique_click_score, false);
});

Deno.test("syncMailchimpEngagementForNewsletters does not update summary for duplicate RPC status", async () => {
  const supabase = {
    from(table: string) {
      return {
        select() {
          return this;
        },
        eq() {
          return this;
        },
        in(_column: string, values: string[]) {
          if (table === "mailchimp_contact_links") {
            return { data: [], error: null };
          }
          if (table === "contacts") {
            return {
              data: values.includes("person@example.com")
                ? [{ id: "contact-1", email: "person@example.com" }]
                : [],
              error: null,
            };
          }
          return { data: [], error: null };
        },
      };
    },
    rpc() {
      return { data: [{ status: "skipped_existing" }], error: null };
    },
  };

  const stats = await syncMailchimpEngagementForNewsletters(
    supabase as any,
    [{
      id: "newsletter-1",
      mailchimp_campaign_id: "mailchimp-campaign-1",
      campaign_id: "11111111-1111-1111-1111-111111111111",
      subject: "Duplicate campaign",
      audience_id: "list-a",
    }],
    {
      maxEmailsPerCampaign: 1,
      fetchEmailActivityPage: async () => ({
        emails: [{
          email_id: "subscriber-hash",
          email_address: "person@example.com",
          list_id: "list-a",
          activity: [{ action: "open", timestamp: "2026-06-09T00:00:00Z" }],
        }],
      }),
    },
  );

  assertEquals(stats.events_inserted, 0);
  assertEquals(stats.events_skipped_existing, 1);
  assertEquals(stats.summaries_updated, 0);
});
