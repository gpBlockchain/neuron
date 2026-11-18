#!/usr/bin/env python3
"""Parse a GitHub releases/tag or tree URL into mode, repo, and ref.

Only https://github.com/<owner>/<repo>/releases/tag/<tag>
and https://github.com/<owner>/<repo>/tree/<ref> are accepted.
The token is never read or forwarded; callers must build their own
api.github.com / github.com URLs from the returned owner/repo/ref.
"""
from __future__ import annotations

import re
import sys
from urllib.parse import unquote, urlparse

ALLOWED_HOST = "github.com"
REPO_PART_RE = re.compile(r"^[A-Za-z0-9._-]+$")
REF_RE = re.compile(r"^[A-Za-z0-9._/~+-]+$")


class GitHubUrlError(ValueError):
    pass


def _reject(reason: str) -> None:
    raise GitHubUrlError(reason)


def parse_github_client_url(raw: str) -> tuple[str, str, str]:
    if raw is None:
        _reject("URL is empty")
    url = raw.strip().replace("\r", "").replace("\n", "")
    if not url:
        _reject("URL is empty")
    if any(ch.isspace() for ch in url):
        _reject("URL must not contain whitespace")

    parsed = urlparse(url)
    if parsed.scheme.lower() != "https":
        _reject("only https://github.com URLs are accepted")
    if parsed.username is not None or parsed.password is not None:
        _reject("userinfo is not allowed in the URL")
    if parsed.hostname is None or parsed.hostname.lower() != ALLOWED_HOST:
        _reject("only the github.com host is accepted")
    if parsed.port not in (None, 443):
        _reject("unexpected port")

    # Split on literal '/' first so %2F stays inside a single ref segment.
    path = parsed.path or ""
    if path != path.strip():
        _reject("invalid path")
    parts = [p for p in path.split("/") if p != ""]
    if not parts:
        _reject("URL path is empty")
    decoded = [unquote(part) for part in parts]
    if len(decoded) < 2:
        _reject("URL must be /<owner>/<repo>/releases/tag/<tag> or /<owner>/<repo>/tree/<ref>")

    owner, repo = decoded[0], decoded[1]
    if not REPO_PART_RE.match(owner) or not REPO_PART_RE.match(repo):
        _reject("invalid repository owner or name")
    if repo.endswith(".git"):
        _reject("repository name must not include .git")

    if len(decoded) < 4:
        _reject("only /releases/tag/<tag> or /tree/<ref> URLs are accepted")

    kind = decoded[2]
    if kind == "releases":
        if decoded[3] != "tag":
            _reject("only /releases/tag/<tag> Release URLs are accepted")
        if len(decoded) < 5 or not decoded[4]:
            _reject("missing release tag")
        if len(decoded) > 5:
            _reject("unexpected path after the release tag; percent-encode slashes in the tag as %2F")
        ref = decoded[4]
        mode = "release"
    elif kind == "tree":
        if not decoded[3]:
            _reject("missing tree ref")
        if len(decoded) > 4:
            _reject("unexpected path after the tree ref; percent-encode slashes in the branch as %2F")
        ref = decoded[3]
        mode = "source"
    else:
        _reject("only /releases/tag/<tag> or /tree/<ref> URLs are accepted")

    if not ref or ref in (".", "..") or "\\" in ref:
        _reject("invalid ref")
    if not REF_RE.match(ref):
        _reject("invalid characters in ref")

    return mode, f"{owner}/{repo}", ref


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print("usage: parse-github-client-url.py <url>", file=sys.stderr)
        return 2
    try:
        mode, repo, ref = parse_github_client_url(argv[1])
    except GitHubUrlError as exc:
        # Never echo the raw URL; it may contain userinfo or a token.
        print(f"Invalid GitHub URL: {exc}", file=sys.stderr)
        return 1
    # Stable, token-free machine output for the shell wrapper.
    print(f"MODE={mode}")
    print(f"REPO={repo}")
    print(f"REF={ref}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
