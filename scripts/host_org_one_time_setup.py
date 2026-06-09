#!/usr/bin/env python3
"""One-time host-organization setup and email-scope rebuild.

This is intentionally not part of the schema migration. Run it after the
KAN-16 backend migration has deployed, using explicit domains for the current
environment.

Examples:
    SUPABASE_URL=https://... SUPABASE_SERVICE_ROLE_KEY=... \
      python3 scripts/host_org_one_time_setup.py --domain pdmedical.com.au --dry-run

    SUPABASE_URL=https://... SUPABASE_SERVICE_ROLE_KEY=... \
      python3 scripts/host_org_one_time_setup.py --domain pdmedical.com.au
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from typing import Any
from urllib.error import HTTPError
from urllib.parse import urlencode
from urllib.request import Request, urlopen


def normalize_domain(value: str) -> str:
    domain = value.strip().lower()
    if "@" in domain:
        domain = domain.rsplit("@", 1)[1]
    return domain.strip(" <>\"")


def require_env(name: str) -> str:
    value = os.getenv(name)
    if not value:
        raise SystemExit(f"Missing required environment variable: {name}")
    return value.rstrip("/")


class SupabaseRest:
    def __init__(self, url: str, key: str) -> None:
        self.base_url = url.rstrip("/")
        self.headers = {
            "Authorization": f"Bearer {key}",
            "apikey": key,
            "Content-Type": "application/json",
        }

    def request(
        self,
        method: str,
        path: str,
        params: dict[str, str] | None = None,
        body: dict[str, Any] | None = None,
        prefer: str | None = None,
    ) -> Any:
        query = f"?{urlencode(params)}" if params else ""
        headers = dict(self.headers)
        if prefer:
            headers["Prefer"] = prefer
        data = json.dumps(body).encode("utf-8") if body is not None else None
        req = Request(
            f"{self.base_url}/rest/v1/{path}{query}",
            data=data,
            headers=headers,
            method=method,
        )
        try:
            with urlopen(req) as resp:
                raw = resp.read().decode("utf-8")
                return json.loads(raw) if raw else None
        except HTTPError as exc:
            raw = exc.read().decode("utf-8")
            raise RuntimeError(f"{method} {path} failed: {exc.code} {raw}") from exc


def load_active_mailbox_domains(client: SupabaseRest) -> list[str]:
    rows = client.request(
        "GET",
        "mailboxes",
        {
            "select": "email",
            "is_active": "eq.true",
        },
    )
    domains = {
        normalize_domain(row["email"])
        for row in rows or []
        if row.get("email")
    }
    return sorted(d for d in domains if d)


def find_organization_ids(client: SupabaseRest, domain: str) -> list[str]:
    direct_orgs = client.request(
        "GET",
        "organizations",
        {
            "select": "id,name,domain,is_host",
            "domain": f"ilike.{domain}",
        },
    )
    alias_rows = client.request(
        "GET",
        "organization_domains",
        {
            "select": "organization_id,domain",
            "domain": f"ilike.{domain}",
        },
    )

    ids = {row["id"] for row in direct_orgs or [] if row.get("id")}
    ids.update(
        row["organization_id"]
        for row in alias_rows or []
        if row.get("organization_id")
    )
    return sorted(ids)


def mark_host(client: SupabaseRest, org_ids: list[str]) -> None:
    id_filter = f"in.({','.join(org_ids)})"
    client.request(
        "PATCH",
        "organizations",
        {"id": id_filter},
        {"is_host": True},
        prefer="return=minimal",
    )


def rebuild_scope(client: SupabaseRest, domain: str) -> None:
    client.request(
        "POST",
        "rpc/rebuild_email_scopes_for_domain",
        body={"p_domain": domain},
    )


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Mark host organizations and rebuild historical email scope."
    )
    parser.add_argument(
        "--domain",
        action="append",
        default=[],
        help="Host domain to mark/rebuild. May be passed more than once.",
    )
    parser.add_argument(
        "--from-active-mailboxes",
        action="store_true",
        help="Use active mailbox domains as the domain list.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print planned changes without updating organizations or emails.",
    )
    parser.add_argument(
        "--skip-rebuild",
        action="store_true",
        help="Only mark organizations as host; do not rebuild emails.is_internal.",
    )
    args = parser.parse_args()

    url = require_env("SUPABASE_URL")
    key = os.getenv("SUPABASE_SERVICE_ROLE_KEY") or os.getenv("SUPABASE_KEY")
    if not key:
        raise SystemExit(
            "Missing SUPABASE_SERVICE_ROLE_KEY or SUPABASE_KEY environment variable"
        )

    client = SupabaseRest(url, key)
    domains = [normalize_domain(d) for d in args.domain]
    if args.from_active_mailboxes:
        domains.extend(load_active_mailbox_domains(client))
    domains = sorted({d for d in domains if d})

    if not domains:
        raise SystemExit("Provide --domain at least once or use --from-active-mailboxes")

    for domain in domains:
        org_ids = find_organization_ids(client, domain)
        if not org_ids:
            print(f"{domain}: no matching organization found")
            continue

        print(f"{domain}: matching organizations: {', '.join(org_ids)}")
        if args.dry_run:
            print(f"{domain}: dry run, not marking host or rebuilding email scope")
            continue

        mark_host(client, org_ids)
        print(f"{domain}: marked organizations as host")

        if not args.skip_rebuild:
            rebuild_scope(client, domain)
            print(f"{domain}: rebuilt emails.is_internal")

    return 0


if __name__ == "__main__":
    sys.exit(main())
