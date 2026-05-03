#!/usr/bin/env python3
"""
Build organization seed SQL from the Australian healthcare facilities dataset.

Inputs:
    db-backups/2026-02-09/main_data.sql  (COPY-format dump of public.organizations)

Output:
    supabase/seed/org_seed.sql           (idempotent seed: parents + facilities + aliases)

Usage:
    python3 scripts/build_org_seed.py [--src PATH] [--out PATH]

Spec: docs/superpowers/specs/2026-04-30-contact-enrichment-design.md §1.2
"""
from __future__ import annotations

import argparse
import re
import sys
import uuid
from collections import defaultdict
from pathlib import Path
from typing import NamedTuple


# ----------------------------------------------------------------------------
# COPY column order from main_data.sql line 84
# ----------------------------------------------------------------------------
COLS = [
    "id", "name", "domain", "phone", "address", "industry", "website", "status",
    "tags", "custom_fields", "created_at", "updated_at", "organization_type_id",
    "region", "hospital_category", "city", "state", "key_hospital",
    "street_address", "suburb", "facility_type", "bed_count", "top_150_ranking",
    "general_info", "products_sold", "has_maternity", "has_operating_theatre",
    "typical_job_roles", "contact_count", "enriched_from_signatures_at", "auth_user_id",
]
IDX = {c: i for i, c in enumerate(COLS)}


# ----------------------------------------------------------------------------
# Reference org_types (mirrors organization_types seed migration)
# ----------------------------------------------------------------------------
ORG_TYPE_IDS = {
    "Hospital":         "1bf02328-60da-4896-ad88-9bd8b056b5e8",
    "Clinic":           "38b11fc7-bbe2-4330-9577-cb5d28a8b531",
    "Aged Care":        "c82f6514-3ea8-4327-b61e-a432e650f53e",
    "Pharmacy":         "427dbb30-aa5c-4e2d-8f2a-6d2965c09363",
    "Medical Supplier": "01513679-35dd-4be4-92e2-d8fc14a51e04",
    "Other":            "f31acc80-4613-457a-b3b5-02cc13cf72a2",
    "Government":       "00000000-0000-4000-8000-000000000001",
    "Education":        "00000000-0000-4000-8000-000000000002",
}


STATE_NORMALIZE = {
    "NSW": "NSW", "VIC": "VIC", "VICTORIA": "VIC",
    "QLD": "QLD", "WA": "WA", "SA": "SA",
    "TAS": "TAS", "ACT": "ACT", "NT": "NT",
    "NEW SOUTH WALES": "NSW",
}


# Hand-curated parent network map. Domain -> (parent name, org type, top-level parent name or None).
# Top-level chain: NSW Health is itself a top-level org; LHDs reference NSW Health as their top.
NSW_HEALTH = "NSW Health"
QLD_HEALTH = "Queensland Health"

PARENTS: dict[str, tuple[str, str, str | None]] = {
    # NSW Health top + 17 LHDs
    "health.nsw.gov.au":           (NSW_HEALTH, "Government", None),
    "cclhd.health.nsw.gov.au":     ("Central Coast LHD", "Government", NSW_HEALTH),
    "farwslhd.health.nsw.gov.au":  ("Far West LHD", "Government", NSW_HEALTH),
    "fwlhd.health.nsw.gov.au":     ("Far West LHD", "Government", NSW_HEALTH),
    "islhd.health.nsw.gov.au":     ("Illawarra Shoalhaven LHD", "Government", NSW_HEALTH),
    "mlhd.health.nsw.gov.au":      ("Murrumbidgee LHD", "Government", NSW_HEALTH),
    "mnclhd.health.nsw.gov.au":    ("Mid North Coast LHD", "Government", NSW_HEALTH),
    "nbmlhd.health.nsw.gov.au":    ("Nepean Blue Mountains LHD", "Government", NSW_HEALTH),
    "ncahs.health.nsw.gov.au":     ("North Coast Area Health Service", "Government", NSW_HEALTH),
    "nnswlhd.health.nsw.gov.au":   ("Northern NSW LHD", "Government", NSW_HEALTH),
    "nslhd.health.nsw.gov.au":     ("Northern Sydney LHD", "Government", NSW_HEALTH),
    "schn.health.nsw.gov.au":      ("Sydney Children's Hospitals Network", "Government", NSW_HEALTH),
    "seslhd.health.nsw.gov.au":    ("South Eastern Sydney LHD", "Government", NSW_HEALTH),
    "slhd.health.nsw.gov.au":      ("Sydney LHD", "Government", NSW_HEALTH),
    "snswlhd.health.nsw.gov.au":   ("Southern NSW LHD", "Government", NSW_HEALTH),
    "swslhd.health.nsw.gov.au":    ("South Western Sydney LHD", "Government", NSW_HEALTH),
    "wnswlhd.health.nsw.gov.au":   ("Western NSW LHD", "Government", NSW_HEALTH),
    "wslhd.health.nsw.gov.au":     ("Western Sydney LHD", "Government", NSW_HEALTH),
    "hnehealth.nsw.gov.au":        ("Hunter New England LHD", "Government", NSW_HEALTH),
    "healthshare.nsw.gov.au":      ("HealthShare NSW", "Government", NSW_HEALTH),

    # Other state health departments
    "health.qld.gov.au":           (QLD_HEALTH, "Government", None),
    "metronorth.health.qld.gov.au": ("Metro North HHS", "Government", QLD_HEALTH),
    "metrosouth.health.qld.gov.au": ("Metro South HHS", "Government", QLD_HEALTH),
    "townsville.health.qld.gov.au": ("Townsville HHS", "Government", QLD_HEALTH),
    "cairns.health.qld.gov.au":     ("Cairns and Hinterland HHS", "Government", QLD_HEALTH),
    "health.tas.gov.au":           ("Tasmania Health", "Government", None),
    "sahealth.sa.gov.au":          ("SA Health", "Government", None),
    "wacountry.health.wa.gov.au":  ("WA Country Health Service", "Government", None),
    "health.wa.gov.au":            ("WA Health", "Government", None),
    "health.vic.gov.au":           ("Victoria Health", "Government", None),
    "sa.gov.au":                   ("SA Government", "Government", None),
    "nsw.gov.au":                  ("NSW Government", "Government", None),
    "nt.gov.au":                   ("NT Government", "Government", None),
    "canberrahealthservices.act.gov.au": ("Canberra Health Services", "Government", None),
    "health.gov.au":               ("Australian Government Department of Health", "Government", None),

    # Big private networks
    "sjog.org.au":           ("St John of God Health Care", "Hospital", None),
    "ramsayhealth.com.au":   ("Ramsay Health Care", "Hospital", None),
    "calvarycare.org.au":    ("Calvary Health Care", "Hospital", None),
    "mater.org.au":          ("Mater Health Services", "Hospital", None),
    "healthecare.com.au":    ("Healthe Care Australia", "Hospital", None),
    "healthscope.com.au":    ("Healthscope", "Hospital", None),
    "healthscopehospitals.com.au": ("Healthscope Hospitals", "Hospital", None),
    "iconcancercentre.com.au": ("Icon Cancer Centre", "Hospital", None),
    "genesiscare.com":         ("GenesisCare", "Hospital", None),
    "curagroup.com.au":        ("Cura Group", "Hospital", None),
    "epworth.org.au":          ("Epworth HealthCare", "Hospital", None),
    "nexushospitals.com.au":   ("Nexus Hospitals", "Hospital", None),
    "mercyhealth.com.au":      ("Mercy Health", "Hospital", None),
    "freseniusmedicalcare.com.au": ("Fresenius Medical Care", "Hospital", None),

    # Single-org rollups
    "monashhealth.org":       ("Monash Health", "Hospital", None),
    "alfredhealth.org.au":    ("Alfred Health", "Hospital", None),
    "austin.org.au":          ("Austin Health", "Hospital", None),
    "easternhealth.org.au":   ("Eastern Health", "Hospital", None),
    "westernhealth.org.au":   ("Western Health", "Hospital", None),
    "nh.org.au":              ("Northern Health", "Hospital", None),
    "rch.org.au":             ("Royal Children's Hospital", "Hospital", None),
    "thermh.org.au":          ("The Royal Melbourne Hospital", "Hospital", None),
    "thewomens.org.au":       ("The Royal Women's Hospital", "Hospital", None),
    "svhm.org.au":            ("St Vincent's Hospital Melbourne", "Hospital", None),
    "svha.org.au":            ("St Vincent's Health Australia", "Hospital", None),
    "svh.org.au":             ("St Vincent's Hospital Sydney", "Hospital", None),
    "svhs.org.au":            ("St Vincent's Health Sydney", "Hospital", None),
    "svph.org.au":            ("St Vincent's Private Hospital", "Hospital", None),
    "svphb.org.au":           ("St Vincent's Private Hospital Brisbane", "Hospital", None),
    "barwonhealth.org.au":    ("Barwon Health", "Hospital", None),
    "gvhealth.org.au":        ("Goulburn Valley Health", "Hospital", None),
    "awh.org.au":             ("Albury Wodonga Health", "Hospital", None),
    "peninsulahealth.org.au": ("Peninsula Health", "Hospital", None),
    "southwesthealthcare.com.au": ("South West Healthcare", "Hospital", None),
    "wwhs.net.au":            ("West Wimmera Health Service", "Hospital", None),
    "ewhs.org.au":            ("East Wimmera Health Service", "Hospital", None),
    "northeasthealth.org.au": ("North East Health Wangaratta", "Hospital", None),
    "chrh.org.au":            ("Cabrini Health", "Hospital", None),
    "genea.com.au":           ("Genea", "Hospital", None),
    "acha.org.au":            ("Adelaide Community Healthcare Alliance", "Hospital", None),
    "adh.org.au":             ("Adelaide Day Hospital", "Hospital", None),
    "cancercare.com.au":      ("Cancer Care", "Hospital", None),
}


ACRONYM_PATTERN = re.compile(
    r"\b("
    r"NSW|VIC|QLD|WA|SA|NT|ACT|TAS|"
    r"LHD|HHS|HSC|PHN|"
    r"NICU|ICU|ED|HDU|CCU|OR|PACU|CSSD|"
    r"PTY|LTD|INC|CO|"
    r"AM|PM|UK|USA|"
    r"CT|MRI|GP|"
    r"AMA|AHPRA|TGA"
    r")\b",
    re.IGNORECASE,
)

NS_UUID = uuid.UUID("6ba7b810-9dad-11d1-80b4-00c04fd430c8")


# ============================================================================
# Pure cleaning functions (unit-tested in test_build_org_seed.py)
# ============================================================================

def is_null(v: str | None) -> bool:
    return v is None or v == r"\N" or v == ""


def smart_title_case(s: str) -> str:
    """Title-case ALL-CAPS strings, preserve mixed-case, re-upper known acronyms.

    Mixed-case input is treated as already-titled and only whitespace-normalised.
    All-caps input gets word-by-word title casing.
    """
    if s is None:
        return s
    s = re.sub(r"\s+", " ", s).strip().rstrip(",").rstrip(";")
    if not s:
        return s
    if any(c.islower() for c in s):
        return s
    out_parts: list[str] = []
    word_re = re.compile(r"^[A-Za-z']+$")
    for tok in re.split(r"(\s|-|/|&|\(|\))", s):
        if not tok:
            continue
        if word_re.match(tok):
            out_parts.append(tok.capitalize())
        else:
            out_parts.append(tok)
    titled = "".join(out_parts)
    titled = ACRONYM_PATTERN.sub(lambda m: m.group(0).upper(), titled)
    titled = re.sub(r"\bMc([a-z])", lambda m: "Mc" + m.group(1).upper(), titled)
    titled = re.sub(r"\bO'([a-z])", lambda m: "O'" + m.group(1).upper(), titled)
    return titled


def normalise_domain(d: str | None) -> str:
    """Lowercase, strip www., strip non-domain chars."""
    if is_null(d):
        return ""
    d = d.strip().lower()
    d = re.sub(r"[^a-z0-9.\-]", "", d)
    d = re.sub(r"^www\.", "", d)
    return d


def normalise_state(s: str | None) -> str:
    """Map dirty state values to canonical 3-letter codes; empty if unknown."""
    if is_null(s):
        return ""
    s = s.strip().rstrip(",").rstrip(";").upper()
    if s in STATE_NORMALIZE:
        return STATE_NORMALIZE[s]
    if s in STATE_NORMALIZE.values():
        return s
    return ""


def normalise_text(s: str | None) -> str:
    """Strip Excel CRLF markers and collapse whitespace."""
    if is_null(s):
        return ""
    s = s.replace("_x000D_", "").replace("\\r\\n", " ").replace("\\n", " ")
    return re.sub(r"\s+", " ", s).strip()


def fill_score(row: list[str]) -> int:
    """Count non-null fields; used to pick the best dedup survivor."""
    return sum(1 for v in row if not is_null(v))


def parse_copy_dump(path: Path) -> list[list[str]]:
    """Read the COPY block for organizations from main_data.sql.

    Looks for the line beginning with `COPY "public"."organizations"` and reads
    rows until the `\\.` terminator. Each row is split on tabs.
    """
    rows: list[list[str]] = []
    in_block = False
    with open(path, encoding="utf-8") as f:
        for line in f:
            if line.startswith('COPY "public"."organizations"'):
                in_block = True
                continue
            if not in_block:
                continue
            if line.startswith("\\."):
                break
            line = line.rstrip("\n")
            if not line:
                continue
            parts = line.split("\t")
            if len(parts) == len(COLS):
                rows.append(parts)
    return rows


def clean_row(raw: list[str]) -> list[str]:
    """Apply normalisation rules to a raw row."""
    row = list(raw)
    row[IDX["name"]] = smart_title_case(row[IDX["name"]])
    row[IDX["domain"]] = normalise_domain(row[IDX["domain"]])
    row[IDX["state"]] = normalise_state(row[IDX["state"]])
    for fld in ("phone", "industry", "website", "general_info", "region",
                "hospital_category", "facility_type", "key_hospital"):
        row[IDX[fld]] = normalise_text(row[IDX[fld]])
    for fld in ("address", "street_address", "city", "suburb"):
        row[IDX[fld]] = smart_title_case(normalise_text(row[IDX[fld]]))
    return row


def dedup(rows: list[list[str]]) -> list[list[str]]:
    """Two-pass dedup. Pass 1: same (lower(name), domain) → keep highest fill_score.
    Pass 2: drop NULL-domain rows whose normalised name appears with a domain elsewhere.
    """
    by_key: dict[tuple[str, str], list[str]] = {}
    for r in rows:
        name = r[IDX["name"]].strip().lower()
        dom = r[IDX["domain"]]
        key = (name, dom)
        if key not in by_key or fill_score(r) > fill_score(by_key[key]):
            by_key[key] = r
    pass1 = list(by_key.values())
    names_with_domain = {r[IDX["name"]].strip().lower() for r in pass1 if r[IDX["domain"]]}
    return [
        r for r in pass1
        if r[IDX["domain"]] or r[IDX["name"]].strip().lower() not in names_with_domain
    ]


def parent_uuid(name: str) -> str:
    """Deterministic UUID5 for a parent org by its display name."""
    return str(uuid.uuid5(NS_UUID, "org-parent:" + name))


def resolve_parent_for_facility(domain: str) -> tuple[str, str] | None:
    """Walk subdomain chain. Return (parent_name, parent_domain) or None."""
    if not domain:
        return None
    if domain in PARENTS:
        return PARENTS[domain][0], domain
    parts = domain.split(".")
    for i in range(1, len(parts) - 1):
        cand = ".".join(parts[i:])
        if cand in PARENTS:
            return PARENTS[cand][0], cand
    return None


# ============================================================================
# SQL emission
# ============================================================================

def sql_str(s: str | None) -> str:
    if s is None or s == "":
        return "NULL"
    return "'" + str(s).replace("'", "''") + "'"


def sql_int(s: str | None) -> str:
    if s is None or s in (r"\N", ""):
        return "NULL"
    return str(s)


def sql_bool(s: str | None) -> str:
    if s == "t":
        return "true"
    return "false"


def emit_parent_row(name: str, domain: str, type_id: str, parent_id_or_null: str) -> str:
    pid = parent_uuid(name)
    return (
        f"  ('{pid}', {sql_str(name)}, {sql_str(domain)}, '{type_id}', "
        f"{parent_id_or_null}, 'Healthcare', 'active', '[]'::jsonb, '{{}}'::jsonb)"
    )


def emit_facility_row(r: list[str], parent_org_id: str | None) -> str:
    type_id = r[IDX["organization_type_id"]]
    if not type_id or type_id == r"\N":
        type_id = ORG_TYPE_IDS["Other"]
    parent_clause = f"'{parent_org_id}'" if parent_org_id else "NULL"
    return (
        "  ("
        f"'{r[IDX['id']]}', "
        f"{sql_str(r[IDX['name']])}, "
        f"{sql_str(r[IDX['domain']] or 'unknown.invalid')}, "  # NOT NULL constraint
        f"{sql_str(r[IDX['phone']] or None)}, "
        f"{sql_str(r[IDX['address']] or None)}, "
        f"{sql_str(r[IDX['industry']] or 'Healthcare')}, "
        f"{sql_str(r[IDX['website']] or None)}, "
        f"'active', "
        f"'{type_id}', "
        f"{sql_str(r[IDX['region']] or None)}, "
        f"{sql_str(r[IDX['hospital_category']] or None)}, "
        f"{sql_str(r[IDX['city']] or None)}, "
        f"{sql_str(r[IDX['state']] or None)}, "
        f"{sql_str(r[IDX['street_address']] or None)}, "
        f"{sql_str(r[IDX['suburb']] or None)}, "
        f"{sql_str(r[IDX['facility_type']] or None)}, "
        f"{sql_int(r[IDX['bed_count']])}, "
        f"{sql_int(r[IDX['top_150_ranking']])}, "
        f"{sql_bool(r[IDX['has_maternity']])}, "
        f"{sql_bool(r[IDX['has_operating_theatre']])}, "
        f"{parent_clause}"
        ")"
    )


# ============================================================================
# Main
# ============================================================================

def build_seed(src: Path, out: Path) -> dict:
    raw = parse_copy_dump(src)
    cleaned = [clean_row(r) for r in raw]
    deduped = dedup(cleaned)

    # Determine parent assignments per facility
    facility_parent_id: list[str | None] = []
    for r in deduped:
        match = resolve_parent_for_facility(r[IDX["domain"]])
        facility_parent_id.append(parent_uuid(match[0]) if match else None)

    # Skip rows that are themselves the parent (same domain + same name)
    facility_rows: list[tuple[list[str], str | None]] = []
    parent_names_lower = {n.lower() for (n, _, _) in PARENTS.values()}
    for r, pid in zip(deduped, facility_parent_id):
        d = r[IDX["domain"]]
        n = r[IDX["name"]].strip()
        if d in PARENTS and n.lower() == PARENTS[d][0].lower():
            continue
        facility_rows.append((r, pid))

    # Domain → expected seed UUID (used by the pre-flight check below)
    parent_domain_to_uuid: dict[str, str] = {}
    seen_parents: set[str] = set()
    for dom, (pname, _, _) in PARENTS.items():
        if pname not in seen_parents:
            seen_parents.add(pname)
            parent_domain_to_uuid[dom] = parent_uuid(pname)
    facility_domain_to_uuid: dict[str, str] = {
        r[IDX["domain"]]: r[IDX["id"]]
        for r, _ in facility_rows
        if r[IDX["domain"]]
    }

    # Build SQL
    out_lines: list[str] = []
    p = out_lines.append
    p("-- =============================================================")
    p("-- Seed: organizations + organization_domains")
    p("-- GENERATED by scripts/build_org_seed.py from")
    p("-- db-backups/2026-02-09/main_data.sql")
    p("-- DO NOT EDIT BY HAND. Re-run the script to regenerate.")
    p("-- Idempotent: ON CONFLICT clauses make re-runs safe.")
    p("-- =============================================================")
    p("")
    p("BEGIN;")
    p("")
    # Pre-flight conflict check. organizations.domain has UNIQUE constraint
    # (customer_organizations_domain_key). If dev already has a row with the
    # same domain but a different id (e.g. auto-created by the pre-RPC
    # intake code), our INSERTs would abort the whole transaction. Fail fast
    # with a clear message and a pointer to the README's pre-clean recipe.
    p("-- Pre-flight: detect domains we want to seed that already belong to")
    p("-- a row with a different id (would otherwise abort on the UNIQUE")
    p("-- constraint customer_organizations_domain_key).")
    p("DO $preflight$")
    p("DECLARE")
    p("  v_count int;")
    p("  v_examples text;")
    p("BEGIN")
    p("  WITH expected(domain, expected_id) AS (VALUES")
    expected_rows = []
    for dom, uid in parent_domain_to_uuid.items():
        expected_rows.append(f"    ({sql_str(dom)}, '{uid}'::uuid)")
    for dom, uid in facility_domain_to_uuid.items():
        expected_rows.append(f"    ({sql_str(dom)}, '{uid}'::uuid)")
    p(",\n".join(expected_rows))
    p("  )")
    p("  SELECT COUNT(*),")
    p("         string_agg(format('%s (existing id %s)', expected.domain, o.id::text), ', ')")
    p("    INTO v_count, v_examples")
    p("    FROM expected")
    p("    JOIN public.organizations o ON o.domain = expected.domain")
    p("   WHERE o.id <> expected.expected_id;")
    p("")
    p("  IF v_count > 0 THEN")
    p("    RAISE EXCEPTION USING")
    p("      MESSAGE = format('Seed pre-flight: %s existing organisations have domains the seed wants to insert with different ids: %s', v_count, v_examples),")
    p("      HINT = 'See supabase/seed/README.md \"Pre-clean for partial-state DBs\" before retrying.';")
    p("  END IF;")
    p("END $preflight$;")
    p("")

    # 1. organization_types reference (idempotent; mirrors schema migration)
    p("-- Reference: organization_types")
    p("INSERT INTO public.organization_types (id, name, description, is_active) VALUES")
    type_rows = [
        (ORG_TYPE_IDS["Hospital"],         "Hospital",         "Hospital or medical center"),
        (ORG_TYPE_IDS["Clinic"],           "Clinic",           "Medical clinic or practice"),
        (ORG_TYPE_IDS["Aged Care"],        "Aged Care",        "Aged care or nursing home facility"),
        (ORG_TYPE_IDS["Pharmacy"],         "Pharmacy",         "Pharmacy or chemist"),
        (ORG_TYPE_IDS["Medical Supplier"], "Medical Supplier", "Medical equipment or supplies vendor"),
        (ORG_TYPE_IDS["Other"],            "Other",            "Other organization type"),
        (ORG_TYPE_IDS["Government"],       "Government",       "Government health body or department"),
        (ORG_TYPE_IDS["Education"],        "Education",        "University, college, or training institution"),
    ]
    p(",\n".join(f"  ('{i}', {sql_str(n)}, {sql_str(d)}, true)" for i, n, d in type_rows))
    p("ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, description = EXCLUDED.description;")
    p("")

    # 2. Top-level parents (parent_organization_id = NULL)
    p("-- Top-level parent organisations")
    p("INSERT INTO public.organizations")
    p("  (id, name, domain, organization_type_id, parent_organization_id,")
    p("   industry, status, tags, custom_fields)")
    p("VALUES")
    top_parent_rows: list[str] = []
    sub_parent_rows: list[str] = []
    seen_parents: set[str] = set()
    for dom, (pname, ptype, top) in PARENTS.items():
        if pname in seen_parents:
            continue
        seen_parents.add(pname)
        type_id = ORG_TYPE_IDS.get(ptype, ORG_TYPE_IDS["Other"])
        if top is None:
            top_parent_rows.append(emit_parent_row(pname, dom, type_id, "NULL"))
        else:
            sub_parent_rows.append(emit_parent_row(pname, dom, type_id, f"'{parent_uuid(top)}'"))
    p(",\n".join(top_parent_rows))
    p("ON CONFLICT (id) DO UPDATE SET")
    p("  name = EXCLUDED.name,")
    p("  domain = EXCLUDED.domain,")
    p("  parent_organization_id = EXCLUDED.parent_organization_id;")
    p("")

    # 3. Sub-parents (LHDs under NSW Health, HHSs under Queensland Health)
    p("-- Sub-parent organisations (linked to a top-level parent)")
    p("INSERT INTO public.organizations")
    p("  (id, name, domain, organization_type_id, parent_organization_id,")
    p("   industry, status, tags, custom_fields)")
    p("VALUES")
    p(",\n".join(sub_parent_rows))
    p("ON CONFLICT (id) DO UPDATE SET")
    p("  name = EXCLUDED.name,")
    p("  domain = EXCLUDED.domain,")
    p("  parent_organization_id = EXCLUDED.parent_organization_id;")
    p("")

    # 4. Facility orgs (cleaned, with parent_organization_id where derivable)
    p("-- Facility organisations (cleaned + linked to parent where known)")
    p("INSERT INTO public.organizations")
    p("  (id, name, domain, phone, address, industry, website, status,")
    p("   organization_type_id, region, hospital_category, city, state,")
    p("   street_address, suburb, facility_type, bed_count, top_150_ranking,")
    p("   has_maternity, has_operating_theatre, parent_organization_id)")
    p("VALUES")
    p(",\n".join(emit_facility_row(r, pid) for r, pid in facility_rows))
    p("ON CONFLICT (id) DO UPDATE SET")
    p("  name                   = EXCLUDED.name,")
    p("  domain                 = EXCLUDED.domain,")
    p("  city                   = EXCLUDED.city,")
    p("  state                  = EXCLUDED.state,")
    p("  street_address         = EXCLUDED.street_address,")
    p("  suburb                 = EXCLUDED.suburb,")
    p("  facility_type          = EXCLUDED.facility_type,")
    p("  parent_organization_id = EXCLUDED.parent_organization_id,")
    p("  organization_type_id   = EXCLUDED.organization_type_id;")
    p("")

    # 5. Domain aliases — exactly one row per domain.
    # ----------------------------------------------------------------
    # organization_domains has UNIQUE INDEX on lower(domain). Multiple
    # facility rows often share a parent's domain (e.g. five facilities
    # all on canberrahealthservices.act.gov.au under the "Canberra Health
    # Services" parent). Per the new design, only the parent claims the
    # canonical alias for the domain; child facilities are reachable via
    # parent_organization_id + the _narrow_to_facility name-similarity
    # match in the RPC. So we dedupe: parent wins; for unclaimed domains,
    # the first-encountered facility wins.
    # When multiple PARENTS keys point at the same parent name (e.g. both
    # `farwslhd.health.nsw.gov.au` and `fwlhd.health.nsw.gov.au` map to
    # "Far West LHD"), the parent owns BOTH aliases — one is_primary=true,
    # the rest are alias-only. Previously only the first-encountered alias
    # was emitted, leaving the other domain to be claimed by a random
    # facility on that domain (an inbound-routing bug).
    p("-- organization_domains: one canonical row per domain")
    p("-- Parents claim every domain they map to (one is_primary, the")
    p("-- rest are alias-only). Standalone facilities whose domain isn't")
    p("-- parent-claimed claim their own. Sibling facilities under a")
    p("-- shared parent domain inherit via parent_organization_id.")
    p("INSERT INTO public.organization_domains (organization_id, domain, is_primary, source) VALUES")
    alias_rows: list[str] = []
    seen_alias_domains: set[str] = set()
    seen_primary_orgs: set[str] = set()
    # Parents first — iterate PARENTS in insertion order so EVERY aliased
    # domain for a given parent gets a row.
    for dom, (pname, _, _) in PARENTS.items():
        if dom in seen_alias_domains:
            continue
        seen_alias_domains.add(dom)
        pid = parent_uuid(pname)
        is_primary = pid not in seen_primary_orgs
        if is_primary:
            seen_primary_orgs.add(pid)
        alias_rows.append(
            f"  ('{pid}', {sql_str(dom)}, {'true' if is_primary else 'false'}, 'seed')"
        )
    # Then facilities for any domain not already claimed by a parent
    for r, _ in facility_rows:
        dom = r[IDX["domain"]]
        if dom and dom not in seen_alias_domains:
            seen_alias_domains.add(dom)
            alias_rows.append(
                f"  ('{r[IDX['id']]}', {sql_str(dom)}, true, 'seed')"
            )
    p(",\n".join(alias_rows))
    p("ON CONFLICT (organization_id, domain) DO UPDATE SET is_primary = EXCLUDED.is_primary;")
    p("")

    p("COMMIT;")
    p("")
    # Stats footer
    parents_with_children = sum(1 for x in facility_parent_id if x)
    p("-- =============================================================")
    p(f"-- Source rows:        {len(raw)}")
    p(f"-- After dedup:        {len(deduped)}")
    p(f"-- Top-level parents:  {len(top_parent_rows)}")
    p(f"-- Sub-parents:        {len(sub_parent_rows)}")
    p(f"-- Facility rows:      {len(facility_rows)}")
    p(f"-- Facilities w/parent: {parents_with_children}")
    p("-- =============================================================")

    out.write_text("\n".join(out_lines) + "\n")
    return {
        "source_rows": len(raw),
        "deduped_rows": len(deduped),
        "top_parents": len(top_parent_rows),
        "sub_parents": len(sub_parent_rows),
        "facility_rows": len(facility_rows),
        "facilities_with_parent": parents_with_children,
    }


def _project_root() -> Path:
    return Path(__file__).resolve().parent.parent.parent.parent


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    default_src = _project_root() / "db-backups" / "2026-02-09" / "main_data.sql"
    default_out = (
        Path(__file__).resolve().parent.parent
        / "supabase"
        / "seed"
        / "org_seed.sql"
    )
    parser.add_argument("--src", type=Path, default=default_src)
    parser.add_argument("--out", type=Path, default=default_out)
    args = parser.parse_args(argv)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    stats = build_seed(args.src, args.out)
    print(f"Wrote {args.out}")
    for k, v in stats.items():
        print(f"  {k}: {v}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
