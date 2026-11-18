# Test packaging with unreleased or private CKB clients

The test packaging workflow can obtain the builtin CKB node and
`ckb-light-client` from more than the official public GitHub Releases used
by default.

Default behavior is unchanged: `scripts/download-ckb.sh` still downloads
the official public assets named by `.ckb-version` and `.ckb-light-version`.

## Modes

Each client has a source mode:

- `release` (default): download a Release asset from `owner/repo` at a tag
  (`CKB_REF` / `CKB_LIGHT_REF`). The default repos are
  `nervosnetwork/ckb` and `nervosnetwork/ckb-light-client`.
- `source`: clone `owner/repo` at a branch, tag, or commit SHA and build
  it. Use this for a branch such as `develop`, which is not a Release tag.
- `artifact`: download a GitHub Actions artifact from a workflow run
  (`*_ARTIFACT_RUN_ID` and `*_ARTIFACT_NAME` are required).

A ref of `develop` in `release` mode is treated as a tag name, not as a
git branch. There is no official `develop` Release; use `source` (or an
artifact from a known run) instead.

## How to run

### Workflow dispatch (available on this branch)

Open **Actions → Package Neuron for Test → Run workflow**, select this
branch, and fill the inputs. Official public example (light client
`develop` from source, CKB unchanged):

- `light_client_source`: `source`
- `light_client_repo`: `nervosnetwork/ckb-light-client`
- `light_client_ref`: `develop`

Leave CKB inputs empty to keep the version file defaults.

### `/package` comment

This only uses the workflow file from the repository **default branch**.
Until this change is merged, a `/package` comment will not see the new
flags. After merge, an owner or collaborator can comment:

```
/package --light-client-source source --light-client-ref develop
```

```
/package -test --ckb-source source --ckb-repo nervosnetwork/ckb --ckb-ref develop
```

`key=value` flags are also accepted (`light_client_ref=develop`).

### Push

A push still packages with the default official Releases unless the commit
message contains `[skip package]`. Push does not take source-mode flags;
use workflow dispatch or a `/package` comment.

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
asset names, upload policy, and that constructed URLs never include a
token. They do not compile CKB, do not authenticate to a private
repository, and do not package Neuron.

Source builds on macOS and Windows, private-token access, and artifact
mode against a live Actions run have not been verified here.
