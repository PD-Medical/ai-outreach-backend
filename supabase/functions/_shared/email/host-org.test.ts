import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { classifyIsInternal, isHostDomain } from "./host-org.ts";

const hostDomains = new Set<string>(["pdmedical.com.au"]);

Deno.test("isHostDomain - true for exact host domain", () => {
  assertEquals(isHostDomain("peter@pdmedical.com.au", hostDomains), true);
});

Deno.test("isHostDomain - case-insensitive", () => {
  assertEquals(isHostDomain("Peter@PDMedical.COM.AU", hostDomains), true);
});

Deno.test("isHostDomain - false for non-host", () => {
  assertEquals(isHostDomain("customer@hospital.com", hostDomains), false);
});

Deno.test("isHostDomain - false on empty / malformed", () => {
  assertEquals(isHostDomain("", hostDomains), false);
  assertEquals(isHostDomain("no-at-sign", hostDomains), false);
  assertEquals(isHostDomain(null as unknown as string, hostDomains), false);
});

Deno.test("classifyIsInternal - all internal returns true", () => {
  const result = classifyIsInternal(
    "peter@pdmedical.com.au",
    ["jasmine@pdmedical.com.au"],
    [],
    [],
    hostDomains,
  );
  assertEquals(result, true);
});

Deno.test("classifyIsInternal - mixed returns false", () => {
  const result = classifyIsInternal(
    "peter@pdmedical.com.au",
    ["customer@hospital.com"],
    ["jasmine@pdmedical.com.au"],
    [],
    hostDomains,
  );
  assertEquals(result, false);
});

Deno.test("classifyIsInternal - inbound from customer returns false", () => {
  const result = classifyIsInternal(
    "customer@hospital.com",
    ["peter@pdmedical.com.au"],
    [],
    [],
    hostDomains,
  );
  assertEquals(result, false);
});

Deno.test("classifyIsInternal - empty participants returns false (safe default)", () => {
  const result = classifyIsInternal("", [], [], [], hostDomains);
  assertEquals(result, false);
});

Deno.test("classifyIsInternal - ignores empty strings and nulls in arrays", () => {
  const result = classifyIsInternal(
    "peter@pdmedical.com.au",
    ["jasmine@pdmedical.com.au", "", null as unknown as string],
    [],
    [],
    hostDomains,
  );
  assertEquals(result, true);
});
