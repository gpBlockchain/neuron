# Test packaging with unreleased or private CKB clients

The test packaging workflow can obtain the builtin CKB node and
`ckb-light-client` from more than the official public GitHub Releases used
by default.

Default behavior is unchanged: if you do not fill a branch/ref,
`scripts/download-ckb.sh` still downloads the official public assets named
by `.ckb-version` and `.ckb-light-version`.

## Choosing a client in Actions

The intended manual UI is **workflow_dispatch** text inputs. CKB and
ckb-light-client are independent.

Preferred fields:

- `ckb_url` / `light_client_url`: a GitHub URL that selects both the
  repository and the obtain mode.
  - Download a Release: `https://github.com/<owner>/<repo>/releases/tag/<tag>`
  - Build a branch, tag, or SHA from source:
    `https://github.com/<owner>/<repo>/tree/<ref>`
  - Official public example (light client `develop` from source):
    `https://github.com/nervosnetwork/ckb-light-client/tree/develop`

Leave a URL empty to fall back to the matching `*_repo` / `*_ref` fields,
or to the official Release named by `.ckb-version` / `.ckb-light-version`
when those are also empty.

Compatibility fields `ckb_repo`, `ckb_ref`, `light_client_repo`, and
`light_client_ref` still work. Filling only a ref still selects source
mode. If a URL is provided together with repo, ref, or an explicit source
mode, the values must match the URL; conflicts are rejected rather than
silently overridden.

Only `https://github.com/...` URLs are accepted. Userinfo, other hosts,
`releases/download` asset links, and extra path segments after `/tree/`
are rejected. If a branch name contains slashes, percent-encode them as
`%2F` instead of adding extra unencoded path segments. The workflow never
sends `NEURON_DEP_GITHUB_TOKEN` to a host taken from a user-supplied URL;
it only calls `api.github.com` and `github.com` using the parsed
`owner/repo` and ref.

These are ordinary text inputs. GitHub Actions cannot show a live dropdown
of branches from another repository.

`upload_packages` still controls artifact upload and is forced off when a
non-official client repo is used.

### When "Run workflow" is available

`workflow_dispatch` only appears in the Actions tab, and only receives
events, after the workflow file on the repository **default branch**
(`develop` here) includes `on: workflow_dispatch`. Pushing this change
only to `wasm` does **not** let you click **Run workflow** yet, and
`gh workflow run` / the API also require the trigger to be registered on
the default branch.

Until that is on `develop`, you can still:

- Review and merge this change (or copy the `workflow_dispatch` block)
  into the default branch, then run the workflow and select the `wasm`
  branch in the branch dropdown.
- Use a `/package` comment **after** the default-branch workflow has the
  new flags. Until then, `/package` still uses the default-branch
  workflow and will not see the new behavior.

Do not treat a push to `wasm` as a way to pick branches: a push without
these inputs still packages official Releases (unless the commit message
contains `[skip package]`).

## `/package` comment (after default-branch registration)

```
/package --light-client-url https://github.com/nervosnetwork/ckb-light-client/tree/develop
```

```
/package -test --ckb-ref develop --light-client-ref develop
```

`key=value` flags are also accepted (`light_client_ref=develop`).
Filling only a ref enters source mode. Explicit
`--light-client-source release --light-client-ref v0.5.4` keeps
Release mode.

## Private repositories

The default `GITHUB_TOKEN` is scoped to this repository only and cannot
read another private repository. For a private CKB or light-client
repository, create a repository Actions secret named
`NEURON_DEP_GITHUB_TOKEN` (suggested new secret; it is not required for
official public sources).

Minimum token permissions:

- **Contents: Read** — clone source or download private Release assets
- **Actions: Read** — only when using `artifact` mode

Use a GitHub App installation token or a fine-grained personal access
token limited to the client repository. Store it as the Actions secret
above. Do not put the token in a URL, a log line, a commit, or a packed
artifact. This workflow passes the secret only as an environment variable
or a git `http.extraheader`.

If the client repository is not the official public `nervosnetwork/ckb`
or `nervosnetwork/ckb-light-client`, the workflow will still try to
package locally but **will not upload** Neuron packages as Actions
artifacts. That avoids publishing private binaries from a public
repository. Set `upload_packages` to `false` to disable uploads even for
official sources.

Do not run a private-source packaging job on a **public** repository.
Workflow inputs and Actions logs on a public repository are visible, so
a private repository name can leak even when artifact upload is skipped.
Use a private fork or a private copy of this workflow for private clients.

## Origin record

A successful obtain step writes `ckb-clients-manifest.json` at the
repository root (gitignored) and includes it in the packaged app when
present. The file records source mode, repo, ref, resolved commit SHA
when available, asset name, and sha256 of the copied binary.

## Local checks

```
bash scripts/tests/ckb-clients.test.sh
```

These tests cover default resolution, comment/input parsing, official
asset names, the "ref only implies source" rule, upload policy, dispatch
input limits, and that constructed URLs never include a token. They do
not compile CKB, do not authenticate to a private repository, and do not
package Neuron.

Source builds on macOS and Windows, private-token access, and artifact
mode against a live Actions run have not been verified here.
