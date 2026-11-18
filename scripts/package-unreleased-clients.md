# Test packaging with unreleased or private CKB clients

The test packaging workflow can obtain the builtin CKB node and
`ckb-light-client` from more than the official public GitHub Releases used
by default.

Default behavior is unchanged: if you do not fill a branch/ref,
`scripts/download-ckb.sh` still downloads the official public assets named
by `.ckb-version` and `.ckb-light-version`.

## Choosing a branch in Actions

The intended manual UI is **workflow_dispatch** inputs:

- `ckb_repo` / `light_client_repo`: optional `owner/name` text fields.
  Leave empty for `nervosnetwork/ckb` and `nervosnetwork/ckb-light-client`.
- `ckb_ref` / `light_client_ref`: the branch, tag, or commit SHA to **build
  from source**. Filling only a ref (for example `develop`) selects source
  mode. You do not need a separate source/release switch for this case.
- Leave both refs empty to keep the official Release path.
- `upload_packages`: whether to upload Neuron packages as artifacts.
  Uploads are forced off when a non-official client repo is used.

These are ordinary text inputs. GitHub Actions cannot show a live dropdown
of branches from another repository, so type the branch name yourself.

If a ref is filled without an explicit source mode, the workflow builds from
source. That avoids treating `develop` as a Release tag (there is no
official `develop` Release). Advanced overrides still exist: set
`CKB_SOURCE` / `CKB_LIGHT_SOURCE` to `release` or `artifact` via a
`/package` comment if you need those modes.

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
/package --light-client-ref develop
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
