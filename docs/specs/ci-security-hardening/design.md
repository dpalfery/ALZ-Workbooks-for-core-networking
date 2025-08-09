# Design Document

## Overview
This document specifies the CI security hardening design for GitHub Actions, adding Terraform IaC scanning via [tool("trivy config")](docs/specs/ci-security-hardening/design.md:1), Snyk IaC via [tool("snyk iac")](docs/specs/ci-security-hardening/design.md:1), secrets scanning via [tool("trufflehog")](docs/specs/ci-security-hardening/design.md:1), and linting for Terraform and PowerShell on every push and pull request. CodeQL is excluded for this repository due to lack of supported languages. The workflow file will be [ .github/workflows/security.yml ](.github/workflows/security.yml), executing in parallelized jobs with caching, SARIF artifact publication (for Trivy and Snyk), and optional SARIF upload to GitHub “Code scanning alerts”.

Key goals:
- Always-on scanning for pushes and PRs with path-based short-circuiting
- Fail the run on “high” severity findings (configurable) in [tool("trivy config")](docs/specs/ci-security-hardening/design.md:1) and [tool("snyk iac")](docs/specs/ci-security-hardening/design.md:1); fail on verified/high-confidence secrets in [tool("trufflehog")](docs/specs/ci-security-hardening/design.md:1)
- Fast feedback through caching and parallelism
- SARIF outputs and clear summaries; auditable waivers
- Minimal permissions and secure secret handling (SNYK_TOKEN)

References (research):
- Trivy action and config scanning: https://github.com/aquasecurity/trivy-action
- Trivy SARIF: https://aquasecurity.github.io/trivy/latest/integrations/github-security/gh-actions/
- Snyk IaC GitHub Action and CLI: https://github.com/snyk/actions and https://docs.snyk.io/scan-with-snyk/iac
- TruffleHog GitHub Action: https://github.com/trufflesecurity/trufflehog-actions-scan
- GitHub upload SARIF action: https://github.com/github/codeql-action/tree/main/upload-sarif
- HashiCorp setup-terraform action: https://github.com/hashicorp/setup-terraform
- PSScriptAnalyzer: https://github.com/PowerShell/PSScriptAnalyzer
- Paths filter for conditional jobs: https://github.com/dorny/paths-filter

## Architecture
```mermaid
flowchart TD
  subgraph GH[GitHub Events]
    P[Push] --> T[Paths Filter]
    PR[Pull Request] --> T
  end

  T -- terraform/** or scripts/** changed --> J1[Job: Lint]
  T -- terraform/** changed --> J2[Job: Trivy (config)]
  T -- terraform/** changed --> J3[Job: Snyk IaC]
  T -- any change --> J4[Job: TruffleHog]

  J1 --> A1[Artifacts: Lint logs]
  J2 --> A2[Artifacts: trivy.sarif]
  J3 --> A3[Artifacts: snyk-iac.sarif]
  J4 --> A4[Artifacts: trufflehog.json]

  A2 --> CS[Upload SARIF (optional)]
  A3 --> CS

  SNYK[(SNYK_TOKEN Secret)] --> J3
```

Top-level workflow: [ .github/workflows/security.yml ](.github/workflows/security.yml) with triggers [github.workflow("on.push")](docs/specs/ci-security-hardening/design.md:1) and [github.workflow("on.pull_request")](docs/specs/ci-security-hardening/design.md:1). A pre-step uses [action("dorny/paths-filter@v3")](docs/specs/ci-security-hardening/design.md:1) to set outputs controlling which jobs run:
- If only docs or markdown changed, run a lightweight success job and skip heavy scans.
- If Terraform changed, run Lint, Trivy, Snyk in parallel.
- If PowerShell changed, run Lint (PSScriptAnalyzer).
- Always run TruffleHog on push and PR, with PRs scoped to diff.

Cache strategy:
- [action("actions/cache@v4")](docs/specs/ci-security-hardening/design.md:1) for Terraform plugin dir (.terraform) per module, and PowerShell module path for PSScriptAnalyzer.
- [action("hashicorp/setup-terraform@v3")](docs/specs/ci-security-hardening/design.md:1) for Terraform tooling.
- Trivy installed via [action("aquasecurity/trivy-action@v0")](docs/specs/ci-security-hardening/design.md:1); no auth cache is stored.

Security and permissions:
- Default GITHUB_TOKEN permissions minimal: [github.workflow_permission("contents: read")](docs/specs/ci-security-hardening/design.md:1) and [github.workflow_permission("security-events: write")](docs/specs/ci-security-hardening/design.md:1) only if SARIF upload is enabled.
- SNYK_TOKEN read from repository secrets; never echoed; debug disabled by default.
- Third-party actions pinned by version or commit SHA.

## Components and Interfaces

1) Workflow file
- File: [ .github/workflows/security.yml ](.github/workflows/security.yml)
- Triggers: [github.workflow("on.push")](docs/specs/ci-security-hardening/design.md:1), [github.workflow("on.pull_request")](docs/specs/ci-security-hardening/design.md:1)
- Concurrency group per ref to avoid duplicate runs on rapid pushes: [github.workflow_key("concurrency")](docs/specs/ci-security-hardening/design.md:1)
- Global env: severity thresholds (e.g., TRIVY_SEVERITY=HIGH, SNYK_SEVERITY_THRESHOLD=high)

2) Paths filter gate
- Action: [action("dorny/paths-filter@v3")](docs/specs/ci-security-hardening/design.md:1)
- Outputs:
  - changed_terraform: bool if terraform/** or modules/** changes
  - changed_powershell: bool if scripts/**/*.ps1 changes
  - trivial_docs: bool if only docs/**/*.md

3) Lint job ([github.workflow_job("lint")](docs/specs/ci-security-hardening/design.md:1))
- Runs on ubuntu-latest (pwsh available) to simplify caching across jobs
- Terraform lint:
  - [action("hashicorp/setup-terraform@v3")](docs/specs/ci-security-hardening/design.md:1)
  - Commands: [terraform.command("fmt -check -recursive")](docs/specs/ci-security-hardening/design.md:1), [terraform.command("validate")](docs/specs/ci-security-hardening/design.md:1) executed in each module/example using a matrix over discovered paths
- PowerShell lint:
  - Install PSScriptAnalyzer: [powershell.command("Install-Module PSScriptAnalyzer -Scope CurrentUser -Force -ErrorAction Stop")](docs/specs/ci-security-hardening/design.md:1)
  - Analyze: [powershell.function("Invoke-ScriptAnalyzer")](docs/specs/ci-security-hardening/design.md:1) with Default rules over [scripts/](scripts)
- Artifacts: lint logs uploaded as text

4) Trivy job ([github.workflow_job("trivy-config")](docs/specs/ci-security-hardening/design.md:1))
- Setup:
  - Checkout with submodules: [action("actions/checkout@v4")](docs/specs/ci-security-hardening/design.md:1)
  - Terraform tool: [action("hashicorp/setup-terraform@v3")](docs/specs/ci-security-hardening/design.md:1)
  - Optional safe init: [terraform.command("init -backend=false")](docs/specs/ci-security-hardening/design.md:1) in each module/example dir (no creds)
- Scan:
  - Install/Run: [action("aquasecurity/trivy-action@v0")](docs/specs/ci-security-hardening/design.md:1) with [trivy.option("scan-type=config")](docs/specs/ci-security-hardening/design.md:1), [trivy.option("format=sarif")](docs/specs/ci-security-hardening/design.md:1), [trivy.option("output=trivy.sarif")](docs/specs/ci-security-hardening/design.md:1), [trivy.option("severity=HIGH,CRITICAL")](docs/specs/ci-security-hardening/design.md:1)
  - Honor [.trivyignore](.trivyignore) if present
  - Execute per Terraform directory via a matrix
- Outputs:
  - Artifact: trivy.sarif
  - Optional upload: [action("github/codeql-action/upload-sarif@v3")](docs/specs/ci-security-hardening/design.md:1)

5) Snyk IaC job ([github.workflow_job("snyk-iac")](docs/specs/ci-security-hardening/design.md:1))
- Setup:
  - Checkout: [action("actions/checkout@v4")](docs/specs/ci-security-hardening/design.md:1)
  - Install: [action("snyk/actions/setup@v3")](docs/specs/ci-security-hardening/design.md:1)
- Scan:
  - Auth via [env("SNYK_TOKEN")](docs/specs/ci-security-hardening/design.md:1) from repo secret
  - Execute [snyk.command("iac test terraform/ --severity-threshold=high --sarif-file-output=snyk-iac.sarif")](docs/specs/ci-security-hardening/design.md:1)
  - If token missing: mark step as skipped with explicit failure summary per requirements
- Outputs:
  - Artifact: snyk-iac.sarif
  - Optional upload: [action("github/codeql-action/upload-sarif@v3")](docs/specs/ci-security-hardening/design.md:1)

6) TruffleHog job ([github.workflow_job("trufflehog")](docs/specs/ci-security-hardening/design.md:1))
- Setup:
  - Checkout: [action("actions/checkout@v4")](docs/specs/ci-security-hardening/design.md:1)
- Scan:
  - Use [action("trufflesecurity/trufflehog-actions-scan@v0")](docs/specs/ci-security-hardening/design.md:1) configured to:
    - On push: scan full repo history HEAD (or latest tree) with redaction
    - On PR: scan only the diff between PR branch and base
    - Respect excludes from [path(".github/trufflehog-exclude.txt")](docs/specs/ci-security-hardening/design.md:1) if present
  - Treat verified or high-confidence findings as failures; lower confidence as warnings
- Outputs:
  - Artifact: trufflehog.json (redacted findings)
  - Step summary with counts; never print raw secrets

7) Waiver governance
- Trivy suppressions via [.trivyignore](.trivyignore) with comments justifying waivers
- Snyk suppressions via [snyk.policy("ignore")](docs/specs/ci-security-hardening/design.md:1) with reason and expiry
- Explicit allowlist/excludes for TruffleHog via [path(".github/trufflehog-exclude.txt")](docs/specs/ci-security-hardening/design.md:1)
- Build surfaces ignore files as artifacts for auditability

8) Summaries and annotations
- Use step summaries:
  - [github.workflow_step("summary")](docs/specs/ci-security-hardening/design.md:1) shows counts by severity
- Inline annotations via SARIF upload for Trivy and Snyk; lint uses problem matchers

## Data Models

- Severity policy:
  - [policy.variable("TRIVY_SEVERITY")](docs/specs/ci-security-hardening/design.md:1) = HIGH (fail), CRITICAL (fail)
  - [policy.variable("SNYK_SEVERITY_THRESHOLD")](docs/specs/ci-security-hardening/design.md:1) = high
- Artifacts:
  - [artifact.type("application/sarif+json")](docs/specs/ci-security-hardening/design.md:1) for trivy.sarif, snyk-iac.sarif
  - [artifact.type("application/json")](docs/specs/ci-security-hardening/design.md:1) for trufflehog.json
- Paths filter config:
  - terraform: terraform/**, modules/**, .terraform.lock.hcl
  - powershell: scripts/**/*.ps1
  - trivial_docs: docs/**, **/*.md

## Error Handling

- Missing SNYK_TOKEN:
  - [snyk.command("auth")](docs/specs/ci-security-hardening/design.md:1) guarded; step reports “token missing” and job fails with actionable message unless a repository variable [policy.variable("ALLOW_SNYK_SKIP")](docs/specs/ci-security-hardening/design.md:1)=true is set
- Terraform init/network:
  - Use [terraform.command("init -backend=false")](docs/specs/ci-security-hardening/design.md:1) to avoid remote backends and credentials
- Action pinning:
  - All third-party actions pinned by version or SHA; workflow fails if unpinned usage is introduced
- Waiver policy:
  - Warn or fail if a suppression lacks justification or has expired; surfaced in summary
- TruffleHog noise:
  - Use diff-only scans on PRs and excludes file to reduce false positives; treat unverified low-confidence as warnings

## Testing Strategy

- Local dry-run:
  - Validate workflow using [tool("actionlint")](docs/specs/ci-security-hardening/design.md:1) (optional) and GitHub Actions “workflow syntax” checks
- CI verification PR:
  - Introduce benign Terraform and PowerShell changes to trigger all jobs; verify artifacts and summaries
- Threshold tests:
  - Inject a known Trivy high finding in a feature branch to ensure fail-on-high works
  - Run Snyk with a seeded misconfiguration example (in examples/) to verify SARIF and failure
  - Seed a dummy token in a temporary branch to ensure TruffleHog flags it; immediately remove and force-push fix
- Performance:
  - Measure run times before/after caching; ensure typical PRs complete under 8 minutes

## Traceability to Requirements
- Req 1 (CI coverage and triggers): workflow triggers, paths filter, required failure on gated thresholds
- Req 2 (Trivy IaC scanning): Trivy job, SARIF, severity gates, ignore support
- Req 3 (Snyk IaC scanning): snyk-iac job, SNYK_TOKEN usage, SARIF, severity gates, missing token behavior
- Req 4 (Linting): terraform fmt/validate and PSScriptAnalyzer
- Req 5 (Secrets scanning): TruffleHog job, diff-mode on PRs, artifacts
- Req 6 (Performance): caching, parallel jobs
- Req 7 (Reporting): artifacts, summaries, optional SARIF upload
- Req 8 (Governance): waiver mechanisms and audit artifacts
- Req 9 (Documentation): local commands and README updates planned in tasks

## Notes and Implementation Hints
- Prefer running all jobs on ubuntu-latest with [shell("pwsh")](docs/specs/ci-security-hardening/design.md:1) steps for PowerShell to keep runners consistent.
- Discover Terraform directories via a small script (e.g., find terraform modules/examples) to build a matrix at runtime.
- Keep Trivy, Snyk, and actions versions explicit and periodically updated via Dependabot (out of scope here).