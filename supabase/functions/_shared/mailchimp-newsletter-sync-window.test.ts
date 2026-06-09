import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  getAustraliaSydneyHour,
  isWithinMailchimpNewsletterSyncWindow,
  scheduleRateToCron,
} from "./mailchimp-newsletter-sync-window.ts";

Deno.test("scheduleRateToCron limits newsletter sync to 19:00-23:59 UTC", () => {
  assertEquals(scheduleRateToCron("5 minutes"), "*/5 19-23 * * *");
  assertEquals(scheduleRateToCron("10 minutes"), "*/10 19-23 * * *");
  assertEquals(scheduleRateToCron("15 minutes"), "*/15 19-23 * * *");
  assertEquals(scheduleRateToCron("30 minutes"), "*/30 19-23 * * *");
  assertEquals(scheduleRateToCron("1 hour"), "0 19-23 * * *");
});

Deno.test("isWithinMailchimpNewsletterSyncWindow enforces 06:00-09:59 AEST", () => {
  assertEquals(isWithinMailchimpNewsletterSyncWindow(new Date("2026-06-08T19:59:00Z")), false);
  assertEquals(isWithinMailchimpNewsletterSyncWindow(new Date("2026-06-08T20:00:00Z")), true);
  assertEquals(isWithinMailchimpNewsletterSyncWindow(new Date("2026-06-08T23:59:00Z")), true);
  assertEquals(isWithinMailchimpNewsletterSyncWindow(new Date("2026-06-09T00:00:00Z")), false);
});

Deno.test("isWithinMailchimpNewsletterSyncWindow enforces 06:00-09:59 AEDT", () => {
  assertEquals(isWithinMailchimpNewsletterSyncWindow(new Date("2026-01-08T18:59:00Z")), false);
  assertEquals(isWithinMailchimpNewsletterSyncWindow(new Date("2026-01-08T19:00:00Z")), true);
  assertEquals(isWithinMailchimpNewsletterSyncWindow(new Date("2026-01-08T22:59:00Z")), true);
  assertEquals(isWithinMailchimpNewsletterSyncWindow(new Date("2026-01-08T23:00:00Z")), false);
});

Deno.test("getAustraliaSydneyHour resolves DST-aware local hour", () => {
  assertEquals(getAustraliaSydneyHour(new Date("2026-06-08T20:00:00Z")), 6);
  assertEquals(getAustraliaSydneyHour(new Date("2026-01-08T19:00:00Z")), 6);
});
