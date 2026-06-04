import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  namesForMailchimpImport,
  normalizeMailchimpMemberName,
} from "./mailchimp-contacts.ts";

Deno.test("normalizeMailchimpMemberName splits full name in FNAME and strips org hints", () => {
  assertEquals(normalizeMailchimpMemberName("Ian Craig (SCHN)", ""), {
    firstName: "Ian",
    lastName: "Craig",
  });
});

Deno.test("normalizeMailchimpMemberName preserves compound last names from full-name FNAME", () => {
  assertEquals(normalizeMailchimpMemberName("Gary De Lucia", null), {
    firstName: "Gary",
    lastName: "De Lucia",
  });
});

Deno.test("normalizeMailchimpMemberName uses clean FNAME and LNAME when both exist", () => {
  assertEquals(normalizeMailchimpMemberName("Dr Anna", "Chernih"), {
    firstName: "Anna",
    lastName: "Chernih",
  });
});

Deno.test("normalizeMailchimpMemberName handles single-token first names", () => {
  assertEquals(normalizeMailchimpMemberName("Anna", ""), {
    firstName: "Anna",
    lastName: null,
  });
});

Deno.test("namesForMailchimpImport fills missing existing fields only", () => {
  const normalized = normalizeMailchimpMemberName("Ian Craig (SCHN)", "");

  assertEquals(namesForMailchimpImport(normalized, {
    first_name: "Ian",
    last_name: "Craig",
  }), {
    firstName: null,
    lastName: null,
  });

  assertEquals(namesForMailchimpImport(normalized, {
    first_name: "Ian",
    last_name: null,
  }), {
    firstName: null,
    lastName: "Craig",
  });
});
