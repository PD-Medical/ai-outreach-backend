import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  applyMailchimpScoreToState,
  buildMailchimpEngagementExternalId,
  createEmptyMailchimpScoringState,
  mailchimpEngagementScheduleRateToCron,
  mapMailchimpActivity,
  scoreMailchimpActivity,
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

Deno.test("buildMailchimpEngagementExternalId is deterministic and normalizes email", () => {
  const first = buildMailchimpEngagementExternalId({
    campaignId: "abc123",
    email: " Person@Example.COM ",
    action: "click",
    timestamp: "2026-06-09T00:00:00.000Z",
    url: "https://example.com/a?x=1",
    index: 4,
  });
  const second = buildMailchimpEngagementExternalId({
    campaignId: "abc123",
    email: "person@example.com",
    action: "click",
    timestamp: "2026-06-09T00:00:00.000Z",
    url: "https://example.com/a?x=1",
    index: 4,
  });

  assertEquals(first, second);
  assertEquals(first, "mailchimp:abc123:person%40example.com:click:2026-06-09T00%3A00%3A00.000Z:https%3A%2F%2Fexample.com%2Fa%3Fx%3D1");
});
