# Requirements Document

## Introduction

This document defines requirements to augment the GitHub Actions CI pipeline with security scanning on every push and pull request. Tools in scope: Trivy IaC (Terraform via trivy config), Snyk IaC (Terraform), TruffleHog secrets scanning, and linting for Terraform and PowerShell. CodeQL is explicitly out of scope for this repository because primary languages (Terraform, PowerShell, KQL, JSON) are not supported by CodeQL for effective SAST. The outcome is a reliable, fast, and enforceable pipeline that blocks insecure changes while remaining developer-friendly.

## Requirements

### Requirement 1: CI coverage and triggers

**User Story:** As a repository maintainer, I want security checks to run on every push and pull request, so that vulnerabilities are detected before merging to protected branches.

#### Acceptance Criteria

1. WHEN any commit is pushed to any branch THEN the CI workflow in [.github/workflows](.github/workflows) SHALL execute security and lint jobs within 10 minutes of the push.
2. WHEN a pull request is opened or synchronized targeting the default branch THEN the CI workflow SHALL execute the same security and lint jobs and report status back to the PR.
3. IF only non-code files (e.g., Markdown under docs/) change THEN the workflow SHALL be permitted to short-circuit heavy scans via path filters, while still running a lightweight no-op job to report success.
4. WHEN the workflow completes THEN the overall run status SHALL be failing if any gated severity threshold is exceeded in Trivy or Snyk results or if linting or secrets scanning fails.

### Requirement 2: Trivy Terraform IaC scanning

**User Story:** As a platform security engineer, I want Terraform code scanned with Trivy on each change, so that misconfigurations are prevented from reaching production.

#### Acceptance Criteria

1. WHEN the workflow runs THEN Trivy SHALL scan Terraform under [terraform/modules](terraform/modules) and [terraform/examples](terraform/examples) including nested directories using [tool("trivy config")](docs/specs/ci-security-hardening/requirements.md:1).
2. IF Trivy finds issues at or above severity "high" THEN the job SHALL fail; "medium" and "low" SHALL be reported but SHALL NOT fail by default.
3. WHEN a repository Trivy ignore file exists (e.g., [.trivyignore](.trivyignore)) THEN the workflow SHALL honor it to allow documented suppressions with justifications.
4. WHEN Trivy completes THEN the job SHALL produce SARIF output as a build artifact and inline GitHub Annotations on changed lines where available.
5. IF Terraform init is required for module context THEN the workflow SHALL perform a safe, offline [terraform.command("init -backend=false")](docs/specs/ci-security-hardening/requirements.md:1) with a local backend and without credentials.

### Requirement 3: Snyk IaC scanning (Terraform)

**User Story:** As a security reviewer, I want Snyk IaC to validate Terraform against known misconfiguration policies, so that risks are caught using a complementary ruleset.

#### Acceptance Criteria

1. WHEN the workflow runs THEN Snyk IaC SHALL execute [snyk.command("iac test")](docs/specs/ci-security-hardening/requirements.md:1) against [terraform/](terraform) paths using organization defaults.
2. IF the Snyk severity threshold "high" or above is detected THEN the job SHALL fail; "medium" findings SHALL be reported but SHALL NOT fail by default.
3. WHEN Snyk runs THEN the SNYK_TOKEN secret stored as a GitHub Actions secret SHALL be used securely (no echo in logs).
4. WHEN Snyk completes THEN results SHALL be emitted as SARIF and uploaded as an artifact; if GitHub code scanning is available, SARIF SHALL be uploaded to code scanning.
5. IF the SNYK_TOKEN is missing THEN the Snyk step SHALL be skipped with a clearly marked neutral status and the workflow overall SHALL fail with an actionable message unless explicitly configured to allow skip.

### Requirement 4: Linting for Terraform and PowerShell

**User Story:** As a developer, I want fast linting feedback for Terraform and PowerShell, so that style and basic correctness issues are fixed before review.

#### Acceptance Criteria

1. WHEN the workflow runs THEN terraform fmt -check and terraform validate SHALL execute against [terraform/](terraform) directories.
2. WHEN the workflow runs THEN PSScriptAnalyzer SHALL lint PowerShell scripts under [scripts/](scripts) with the Default rule set.
3. IF any linter reports errors THEN the corresponding job SHALL fail and post inline annotations on the PR where possible.
4. WHEN no Terraform or PowerShell files changed in the commit THEN the respective linter job MAY noop quickly using path filters.

### Requirement 5: Secrets scanning with TruffleHog

**User Story:** As a security engineer, I want secrets scanning on every push and PR using TruffleHog, so that leaked credentials and tokens are detected promptly.

#### Acceptance Criteria

1. WHEN the workflow runs THEN TruffleHog SHALL scan the repository for secrets using [action("trufflesecurity/trufflehog-actions-scan")](docs/specs/ci-security-hardening/requirements.md:1) or equivalent CLI with redaction enabled.
2. WHEN running on a pull request THEN TruffleHog SHALL scan only the diff between the PR branch and the target branch to minimize noise, while push events MAY scan the full repository.
3. IF any verified or high-confidence findings are detected THEN the job SHALL fail; low-confidence findings MAY be treated as warnings via configuration.
4. WHEN TruffleHog completes THEN the job SHALL upload a JSON report artifact and include a concise summary in the job output without printing raw secret values.
5. WHEN paths known to contain test fixtures or intentionally non-sensitive tokens exist THEN they MAY be excluded via an explicit allowlist or path excludes held in-repo (e.g., [path(".github/trufflehog-exclude.txt")](docs/specs/ci-security-hardening/requirements.md:1)).

### Requirement 6: Performance, caching, and parallelization

**User Story:** As a maintainer, I want scans to finish quickly, so that developer iteration speed is preserved.

#### Acceptance Criteria

1. WHEN the workflow runs THEN jobs for lint, Trivy, Snyk, and TruffleHog SHALL execute in parallel where feasible.
2. WHEN repeated runs occur on the same commit THEN Terraform plugin and tool caches (PowerShell modules) SHALL be cached to reduce runtime.
3. The total wall-clock time for a typical PR with modest Terraform changes SHALL be under 8 minutes on GitHub-hosted runners.

### Requirement 7: Reporting, artifacts, and traceability

**User Story:** As a reviewer, I want clear summaries and artifacts, so that I can understand and track issues over time.

#### Acceptance Criteria

1. WHEN scans finish THEN the workflow SHALL attach artifacts: trivy.sarif, snyk-iac.sarif, trufflehog.json, and linter logs.
2. WHEN running on a pull request THEN the workflow SHALL post concise summaries with counts by severity and links to artifacts.
3. IF SARIF upload to GitHub code scanning is enabled in the repo THEN results SHALL appear under the Security tab with proper tool names ("trivy", "snyk-iac").

### Requirement 8: Governance, waivers, and baselines

**User Story:** As a security lead, I want a controlled process to suppress false positives, so that the signal remains high without blocking valid changes.

#### Acceptance Criteria

1. WHEN a finding is a known false positive THEN maintainers SHALL be able to suppress it via tool-native mechanisms ([.trivyignore](.trivyignore), Snyk ignore policy) with a required justification and an expiry date where supported.
2. WHEN a suppression is added THEN the workflow SHALL include the ignore file path in the build artifacts for auditability.
3. IF a suppression lacks justification or exceeds a maximum expiry (e.g., 180 days) THEN the job SHALL warn and MAY fail based on a configurable flag.

### Requirement 9: Security of CI and secrets handling

**User Story:** As a security engineer, I want CI to minimize privilege and secret exposure, so that the scanning process does not introduce new risks.

#### Acceptance Criteria

1. WHEN the workflow runs THEN it SHALL use GitHub-hosted runners with default permissions: contents: read, security-events: write (only when SARIF upload is enabled), and minimal additional scopes.
2. WHEN using SNYK_TOKEN THEN the secret SHALL be read from GitHub Actions secrets and never printed; debug logs SHALL be disabled by default.
3. IF third-party actions are used THEN they SHALL be pinned by version or commit SHA.

### Requirement 10: Documentation and developer experience

**User Story:** As a contributor, I want clear documentation to run scans locally, so that I can fix issues before pushing.

#### Acceptance Criteria

1. WHEN onboarding a developer THEN the repository README SHALL include a short section linking to local commands to run Trivy config, Snyk IaC, terraform fmt/validate, and PSScriptAnalyzer, and TruffleHog with safe redaction.
2. WHEN new rules or thresholds are adjusted THEN the changes SHALL be documented in a SECURITY.md or CI section of the README.

## Non-Goals and Exclusions

- CodeQL scanning is excluded for this repository as it primarily contains Terraform, PowerShell, KQL, and JSON which are not covered effectively by CodeQL.
- General-purpose secrets scanning is now explicitly in scope via TruffleHog; no additional scanners are included in this feature.

## Notes and Assumptions

- CI provider is GitHub Actions; workflows will be authored under [.github/workflows](.github/workflows).
- Snyk scope is IaC (Terraform) only; SNYK_TOKEN will be provisioned as a repository secret.
- Existing KQL/JSON lint scripts remain available but are not in scope for this security hardening feature.