# Issue Package Request Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a GitHub Issue Form flow that one-off packages a public GitHub Rime data repository with one selected Weasel variant, uploads the installer as a GitHub Actions artifact, and comments status back to the issue without changing `builds.yaml`.

**Architecture:** Add a small PowerShell request parser/validator module and CLI scripts so behavior is testable outside GitHub Actions. Add an issue template and a separate `package-request.yml` workflow that validates on Ubuntu, builds once on Windows, uploads artifacts, and comments success/failure.

**Tech Stack:** GitHub Actions, PowerShell 7, Pester tests, existing `pack.ps1` and helper scripts.

---

## Chunk 1: Request Parsing and Validation

### Task 1: Add package request parser tests

**Files:**
- Create: `tests/PackageRequest.Tests.ps1`
- Create: `scripts/lib/PackageRequest.psm1`

- [ ] Write failing tests for parsing GitHub Issue Form markdown, normalizing GitHub repo URLs, validating data names, detecting duplicate configured data names, validating single known weasel names, and checking Rime data tree shape.
- [ ] Run `Invoke-Pester tests/PackageRequest.Tests.ps1` and confirm failures are for missing implementation.
- [ ] Implement minimal parser/validator functions in `scripts/lib/PackageRequest.psm1`.
- [ ] Re-run `Invoke-Pester tests/PackageRequest.Tests.ps1`.

### Task 2: Add package request CLI scripts

**Files:**
- Create: `scripts/prepare-package-request.ps1`
- Create: `scripts/check-rime-data-shape.ps1`
- Modify: `tests/PackageRequest.Tests.ps1`

- [ ] Add tests for CLI output JSON/GITHUB_OUTPUT behavior where practical using temp files and env vars.
- [ ] Implement `prepare-package-request.ps1` to parse issue body, validate static fields against `builds.yaml`, emit normalized JSON and outputs.
- [ ] Implement `check-rime-data-shape.ps1` to validate cloned `custom-data` contains `*.schema.yaml` or `default.custom.yaml`.
- [ ] Run package request tests.

## Chunk 2: GitHub Issue Workflow

### Task 3: Add Issue Form and workflow static tests

**Files:**
- Create: `.github/ISSUE_TEMPLATE/package-data.yml`
- Create: `.github/workflows/package-request.yml`
- Modify: `tests/Workflow.Tests.ps1`

- [ ] Add static workflow tests confirming issue-open trigger, label guard, minimal permissions, no `builds.yaml`/state commits, artifact includes issue number, and workflow comments via `gh issue comment`.
- [ ] Run `Invoke-Pester tests/Workflow.Tests.ps1` and confirm new tests fail.
- [ ] Add issue form with package request fields and single-choice weasel dropdown.
- [ ] Add workflow reusing build steps from `build.yml` but without release job.
- [ ] Re-run workflow tests.

## Chunk 3: Full Verification and Review

### Task 4: Full test suite and review

**Files:**
- All changed files

- [ ] Run full Pester suite.
- [ ] Review diffs manually and with subagent review.
- [ ] Fix important findings.
- [ ] Re-run relevant verification.
