#!/usr/bin/env python3
"""Tests for build_org_seed.py cleaning + parent-resolution functions."""
import unittest
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from build_org_seed import (
    smart_title_case,
    normalise_domain,
    normalise_state,
    normalise_text,
    is_null,
    fill_score,
    dedup,
    parent_uuid,
    resolve_parent_for_facility,
    IDX,
    COLS,
    PARENTS,
)


def make_row(**kwargs):
    """Build a 31-col row with \\N defaults; override via kwargs."""
    row = [r"\N"] * len(COLS)
    for k, v in kwargs.items():
        row[IDX[k]] = v
    return row


class TestSmartTitleCase(unittest.TestCase):
    def test_all_caps_to_title(self):
        self.assertEqual(smart_title_case("ABBOTSFORD PRIVATE HOSPITAL"),
                         "Abbotsford Private Hospital")

    def test_mixed_case_preserved(self):
        self.assertEqual(smart_title_case("Abbotsford Private Hospital"),
                         "Abbotsford Private Hospital")
        self.assertEqual(smart_title_case("eHealth NSW"), "eHealth NSW")

    def test_acronyms_re_uppered(self):
        self.assertEqual(smart_title_case("NSW HEALTH"), "NSW Health")
        self.assertEqual(smart_title_case("WAGGA HOSPITAL ICU"),
                         "Wagga Hospital ICU")

    def test_pty_ltd_preserved(self):
        self.assertEqual(smart_title_case("A & M MEDICAL SERVICES PTY LTD"),
                         "A & M Medical Services PTY LTD")

    def test_strip_trailing_punctuation(self):
        self.assertEqual(smart_title_case("HOSPITAL,"), "Hospital")
        self.assertEqual(smart_title_case("CLINIC;"), "Clinic")

    def test_collapse_whitespace(self):
        self.assertEqual(smart_title_case("BILOELA  HOSPITAL  "),
                         "Biloela Hospital")

    def test_mc_oapostrophe(self):
        self.assertEqual(smart_title_case("MCDONALD HOSPITAL"),
                         "McDonald Hospital")
        self.assertEqual(smart_title_case("O'BRIEN MEDICAL"),
                         "O'Brien Medical")

    def test_empty(self):
        self.assertEqual(smart_title_case(""), "")
        self.assertIsNone(smart_title_case(None))


class TestNormaliseDomain(unittest.TestCase):
    def test_lowercase(self):
        self.assertEqual(normalise_domain("Health.NSW.gov.AU"), "health.nsw.gov.au")

    def test_strip_www(self):
        self.assertEqual(normalise_domain("www.example.com"), "example.com")

    def test_strip_stray_chars(self):
        self.assertEqual(normalise_domain("health.qld.gov.au>"),
                         "health.qld.gov.au")

    def test_null_handling(self):
        self.assertEqual(normalise_domain(r"\N"), "")
        self.assertEqual(normalise_domain(None), "")
        self.assertEqual(normalise_domain(""), "")


class TestNormaliseState(unittest.TestCase):
    def test_canonical_codes(self):
        for code in ("NSW", "VIC", "QLD", "WA", "SA", "TAS", "ACT", "NT"):
            self.assertEqual(normalise_state(code), code)

    def test_dirty_values(self):
        self.assertEqual(normalise_state("NSW,"), "NSW")
        self.assertEqual(normalise_state("Vic"), "VIC")
        self.assertEqual(normalise_state("VIC,"), "VIC")
        self.assertEqual(normalise_state("Victoria"), "VIC")

    def test_unknown_returns_empty(self):
        self.assertEqual(normalise_state("Texas"), "")
        self.assertEqual(normalise_state(""), "")


class TestNormaliseText(unittest.TestCase):
    def test_strip_excel_crlf(self):
        self.assertEqual(normalise_text("Foo_x000D_\nBar"), "Foo Bar")

    def test_collapse_whitespace(self):
        self.assertEqual(normalise_text("foo   bar\tbaz"), "foo bar baz")

    def test_null(self):
        self.assertEqual(normalise_text(r"\N"), "")


class TestIsNull(unittest.TestCase):
    def test_pg_null(self):
        self.assertTrue(is_null(r"\N"))

    def test_empty(self):
        self.assertTrue(is_null(""))
        self.assertTrue(is_null(None))

    def test_real_value(self):
        self.assertFalse(is_null("hello"))


class TestFillScore(unittest.TestCase):
    def test_higher_when_more_filled(self):
        sparse = make_row(name="Foo")
        full = make_row(name="Foo", domain="foo.com", phone="123",
                        city="Sydney", state="NSW")
        self.assertGreater(fill_score(full), fill_score(sparse))


class TestDedup(unittest.TestCase):
    def test_keeps_higher_fill_when_same_name_domain(self):
        sparse = make_row(name="Atherton Hospital", domain="health.qld.gov.au")
        full = make_row(name="Atherton Hospital", domain="health.qld.gov.au",
                        city="Atherton", state="QLD", phone="07-4030-0000")
        result = dedup([sparse, full])
        self.assertEqual(len(result), 1)
        self.assertEqual(result[0][IDX["city"]], "Atherton")

    def test_drops_null_domain_when_named_match_exists(self):
        with_dom = make_row(name="Holmesglen Private Hospital",
                            domain="holmesglenprivate.com.au")
        without = make_row(name="Holmesglen Private Hospital", domain="")
        result = dedup([with_dom, without])
        self.assertEqual(len(result), 1)
        self.assertEqual(result[0][IDX["domain"]], "holmesglenprivate.com.au")

    def test_keeps_distinct_names(self):
        a = make_row(name="Wollongong Hospital", domain="islhd.health.nsw.gov.au")
        b = make_row(name="Bowral Hospital",     domain="islhd.health.nsw.gov.au")
        result = dedup([a, b])
        self.assertEqual(len(result), 2)


class TestResolveParent(unittest.TestCase):
    def test_exact_match(self):
        self.assertEqual(resolve_parent_for_facility("ramsayhealth.com.au"),
                         ("Ramsay Health Care", "ramsayhealth.com.au"))

    def test_subdomain_walks_to_lhd(self):
        result = resolve_parent_for_facility("emergency.nslhd.health.nsw.gov.au")
        self.assertIsNotNone(result)
        self.assertEqual(result[0], "Northern Sydney LHD")

    def test_subdomain_walks_to_nsw_health(self):
        # bare nslhd subdomain should hit Northern Sydney LHD before NSW Health
        result = resolve_parent_for_facility("nslhd.health.nsw.gov.au")
        self.assertEqual(result[0], "Northern Sydney LHD")

    def test_unknown_subdomain_walks_to_nsw_health(self):
        # Some random subdomain under .health.nsw.gov.au should match NSW Health
        result = resolve_parent_for_facility("randomthing.health.nsw.gov.au")
        self.assertEqual(result[0], "NSW Health")

    def test_unknown_returns_none(self):
        self.assertIsNone(resolve_parent_for_facility("randomprivateclinic.com.au"))

    def test_empty(self):
        self.assertIsNone(resolve_parent_for_facility(""))


class TestParentUuid(unittest.TestCase):
    def test_deterministic(self):
        a = parent_uuid("NSW Health")
        b = parent_uuid("NSW Health")
        self.assertEqual(a, b)

    def test_distinct_per_name(self):
        self.assertNotEqual(parent_uuid("NSW Health"),
                            parent_uuid("Queensland Health"))


class TestParentMapIntegrity(unittest.TestCase):
    """Sanity checks on the hand-curated PARENTS map."""

    def test_all_top_levels_resolvable(self):
        # Every top-level parent (top is None) should be resolvable from its own domain
        for dom, (name, _, top) in PARENTS.items():
            if top is None:
                result = resolve_parent_for_facility(dom)
                self.assertIsNotNone(result, f"top-level {name} from {dom}")

    def test_subparents_reference_existing_top_levels(self):
        # If a parent has a top, that top must exist in the map's values
        all_parent_names = {n for (n, _, _) in PARENTS.values()}
        for dom, (name, _, top) in PARENTS.items():
            if top is not None:
                self.assertIn(top, all_parent_names,
                              f"sub-parent {name} references unknown top {top}")


if __name__ == "__main__":
    unittest.main(verbosity=2)
