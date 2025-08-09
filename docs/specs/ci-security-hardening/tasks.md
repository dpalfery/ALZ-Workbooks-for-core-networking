# Implementation Plan

This plan converts the approved design into discrete, incremental coding tasks suitable for a code-generation LLM. Tasks are test-driven, avoid big jumps, and reference specific requirements and acceptance criteria from the requirements document. Only code-writing, modification, and testing activities are included.

- [x] 1. Create GitHub Actions workflow skeleton
  - Create workflow file: [`.github/workflows/security.yml`](.github/workflows/security.yml)
  - Define triggers for push and pull_request; set minimal permissions and concurrency:
    - [`github.workflow("on.push")`](.github/workflows/security.yml:1), [`github.workflow("on.pull_request")`](.github/workflows/security.yml:1)
    - [`github.workflow_permission("contents: read")`](.github/workflows/security.yml:1); conditionally enable [`github.workflow_permission("security-events: write")`](.github/workflows/security.yml:1) only when SARIF upload is turned on
    - [`github.workflow_key("concurrency")`](.github/workflows/security.yml:1) group by ref to avoid duplicate runs
  - Add global env for severity thresholds (e.g., `TRIVY_SEVERITY=HIGH,CRITICAL`, `SNYK_SEVERITY_THRESHOLD=high`, `UPLOAD_SARIF=false`)
  - _Requirements: 1.1–1.4, 9.1–9.3_
  - AC Validation: Workflow added with push, pull_request, and workflow_dispatch inputs; top-level permissions set to contents: read; concurrency groups per-ref; env defaults set (TRIVY_SEVERITY, SNYK_SEVERITY_THRESHOLD, UPLOAD_SARIF). SARIF write permission only on SARIF upload jobs.

- [x] 1.1 Add paths filter gate for fast no-op and conditional jobs
  - Add a first job or step using [`action("dorny/paths-filter@v3")`](.github/workflows/security.yml:1) to compute:
    - `changed_terraform` = terraform/**, modules/**, **/.terraform.lock.hcl
    - `changed_powershell` = scripts/**/*.ps1
    - `trivial_docs` = docs/**, **/*.md
  - Expose outputs to control downstream jobs; include a trivial success [`github.workflow_job("noop")`](.github/workflows/security.yml:1) when `trivial_docs == true`
  - _Requirements: 1.1–1.3, 5.1, 6.3_
  - AC Validation: Job [`github.workflow_job("changes")`](.github/workflows/security.yml:1) emits outputs and gates downstream; [`github.workflow_job("noop")`](.github/workflows/security.yml:1) runs on trivial docs unless forced via workflow_dispatch inputs.

- [x] 2. Implement Lint job for Terraform and PowerShell
  - Add [`github.workflow_job("lint")`](.github/workflows/security.yml:1) conditioned to run when `changed_terraform == true || changed_powershell == true`
  - Runner: `ubuntu-latest` with `shell: pwsh` for PowerShell steps
  - Terraform lint:
    - Setup Terraform via [`action("hashicorp/setup-terraform@v3")`](.github/workflows/security.yml:1)
    - Discover Terraform directories dynamically and run:
      - [`terraform.command("fmt -check -recursive")`](.github/workflows/security.yml:1)
      - [`terraform.command("validate")`](.github/workflows/security.yml:1)
  - PowerShell lint:
    - Cache and install PSScriptAnalyzer, then run [`powershell.function("Invoke-ScriptAnalyzer")`](.github/workflows/security.yml:1) against [`scripts/`](scripts)
  - Upload text artifacts: `lint-terraform.txt`, `lint-powershell.txt`
  - _Requirements: 4.1–4.4, 6.1–6.3, 7.1–7.2_
  - AC Validation: Lint job runs terraform fmt/validate across discovered dirs and PSScriptAnalyzer over scripts; artifacts uploaded; job summary prints error counts.

- [x] 2.1 Add caching for faster lint runs
  - Use [`action("actions/cache@v4")`](.github/workflows/security.yml:1) for:
    - PowerShell modules path (e.g., `~/.local/share/powershell/Modules`)
    - Terraform plugin caches keyed by `hashFiles('**/.terraform.lock.hcl')`
  - _Requirements: 5.2–5.3_
  - AC Validation: PowerShell analyzer cache enabled; Terraform plugin cache used in Trivy scan job; TF plugin cache directory is defined globally for reuse.

- [x] 3. Implement Trivy Terraform IaC scan job
  - Add [`github.workflow_job("trivy-config")`](.github/workflows/security.yml:1) conditioned to run when `changed_terraform == true`
  - Steps:
    - Checkout via [`action("actions/checkout@v4")`](.github/workflows/security.yml:1)
    - Setup Terraform via [`action("hashicorp/setup-terraform@v3")`](.github/workflows/security.yml:1)
    - Discover Terraform directories and for each:
      - Run [`terraform.command("init -backend=false")`](.github/workflows/security.yml:1) (no credentials)
      - Execute Trivy via [`action("aquasecurity/trivy-action@v0")`](.github/workflows/security.yml:1) with:
        - [`trivy.option("scan-type=config")`](.github/workflows/security.yml:1)
        - [`trivy.option("severity=${{ env.TRIVY_SEVERITY }}")`](.github/workflows/security.yml:1)
        - [`trivy.option("format=sarif")`](.github/workflows/security.yml:1)
        - [`trivy.option("output=trivy.sarif")`](.github/workflows/security.yml:1)
      - Honor [`.trivyignore`](.trivyignore) automatically if present
  - Upload artifact: `trivy.sarif`; conditionally upload SARIF via [`action("github/codeql-action/upload-sarif@v3")`](.github/workflows/security.yml:1) when `UPLOAD_SARIF == 'true'`
  - Fail the job on HIGH/CRITICAL findings
  - _Requirements: 2.1–2.5, 6.1–6.3, 7.1–7.3, 8.1–8.3_
  - AC Validation: Matrix over Terraform dirs; offline init; Trivy v0 action generates SARIF and fails on HIGH/CRITICAL; artifacts and summary provided; optional SARIF upload job with scoped permissions.

- [x] 3.1 Seed Trivy ignore file (optional, code/config only)
  - Create a placeholder ignore file with guidance comments: [`.trivyignore`](.trivyignore)
  - Include examples requiring justification and suggested expiry format in comments
  - Upload ignore file as an artifact in the Trivy job for auditability
  - _Requirements: 8.1–8.3, 7.2_
  - AC Validation: `.trivyignore` created with guidance; Trivy job uploads the file when present for audit.

- [x] 4. Implement Snyk IaC scan job
  - Add [`github.workflow_job("snyk-iac")`](.github/workflows/security.yml:1) conditioned to run when `changed_terraform == true`
  - Steps:
    - Checkout via [`action("actions/checkout@v4")`](.github/workflows/security.yml:1)
    - Setup Snyk via [`action("snyk/actions/setup@v3")`](.github/workflows/security.yml:1)
    - Guard for token:
      - If `${{ secrets.SNYK_TOKEN }}` is empty and `${{ vars.ALLOW_SNYK_SKIP }}` != 'true', run a small step that prints an actionable summary and exits with failure
    - Execute [`snyk.command("iac test terraform/ --severity-threshold=${{ env.SNYK_SEVERITY_THRESHOLD }} --sarif-file-output=snyk-iac.sarif")`](.github/workflows/security.yml:1)
    - Do not echo token; disable debug
  - Upload artifact: `snyk-iac.sarif`; conditionally upload SARIF via [`action("github/codeql-action/upload-sarif@v3")`](.github/workflows/security.yml:1) when `UPLOAD_SARIF == 'true'`
  - Fail the job on HIGH (and above) findings
  - _Requirements: 3.1–3.5, 6.1–6.3, 7.1–7.3, 9.2_
  - AC Validation: Snyk setup and guarded execution implemented; SARIF artifact produced; optional upload job present; severity threshold enforced via CLI flag.

- [x] 5. Implement TruffleHog secrets scanning job
  - Add [`github.workflow_job("trufflehog")`](.github/workflows/security.yml:1) for all changes (push and PR)
  - Steps:
    - Checkout via [`action("actions/checkout@v4")`](.github/workflows/security.yml:1)
    - Run [`action("trufflesecurity/trufflehog-actions-scan@v0")`](.github/workflows/security.yml:1) configured as:
      - On PR: scan diff between `base` and `head` only
      - On push: scan the current tree (avoid full history by default)
      - Enable redaction; respect excludes from [`.github/trufflehog-exclude.txt`](.github/trufflehog-exclude.txt)
    - Output JSON report `trufflehog.json` (redacted values)
  - Treat verified or high-confidence findings as failures; lower-confidence as warnings
  - Upload artifact: `trufflehog.json`
  - _Requirements: 5.1–5.5, 7.1–7.2_
  - AC Validation: Official action v0 with redaction and excludes; JSON artifact uploaded; summary shows high vs. low/medium counts; defaults avoid full-history scans.

- [x] 5.1 Add TruffleHog excludes file
  - Create path allowlist/excludes file: [`.github/trufflehog-exclude.txt`](.github/trufflehog-exclude.txt) with common non-sensitive patterns (images, docs, test fixtures)
  - Ensure the job reads excludes if present
  - Upload as artifact for auditability
  - _Requirements: 5.5, 8.1–8.3, 7.2_
  - AC Validation: Excludes file added; action arg `--exclude-paths .github/trufflehog-exclude.txt` wired; artifact for results uploaded.

- [x] 6. Implement SARIF upload toggle
  - Add conditional SARIF upload steps in Trivy and Snyk jobs guarded by `if: env.UPLOAD_SARIF == 'true'`
  - Default `UPLOAD_SARIF` to `false` in the workflow env to avoid unexpected security-events permission usage
  - _Requirements: 7.3, 9.1_
  - AC Validation: Separate upload jobs [`github.workflow_job("trivy-sarif-upload")`](.github/workflows/security.yml:1), [`github.workflow_job("snyk-sarif-upload")`](.github/workflows/security.yml:1) with `permissions: security-events: write` only there; gated by UPLOAD_SARIF.

- [x] 7. Add job summaries and annotations
  - After each job finishes, append a concise summary to [`github.workflow_step("summary")`](.github/workflows/security.yml:1) using `$GITHUB_STEP_SUMMARY`, including counts by severity and links to artifacts
  - Ensure failure conditions still produce summaries (use `if: always()`)
  - _Requirements: 7.1–7.2_
  - AC Validation: Each job appends a concise `$GITHUB_STEP_SUMMARY` with `if: always()`, including SARIF upload jobs; noop summary also uses `if: always()`.

- [x] 8. Enforce secure action pinning and secret handling
  - Pin all third-party actions by explicit version (or SHA where required)
  - Ensure no step prints `${{ secrets.SNYK_TOKEN }}`; disable verbose and debug logs by default
  - _Requirements: 9.1–9.3_
  - AC Validation: All actions pinned by major version; comments note SHA pin recommendation for v0 actions; SNYK_TOKEN only passed via env to CLI.

- [x] 9. Optimize execution with caches and parallelism
  - Run Lint, Trivy, Snyk, and TruffleHog jobs in parallel (subject to conditions)
  - Confirm caches for Terraform plugins and PowerShell modules are effective and safe across jobs
  - _Requirements: 5.1–5.3_
  - AC Validation: Jobs are independent except for `changes` and `tf-dirs` needs; caches used for PSScriptAnalyzer and TF plugins to improve runtimes.

- [x] 10. Validate behavior through controlled checks (in-code)
  - Add a temporary workflow dispatch input to force-enable each job for testing without file changes (remove after verification)
  - Verify failure on seeded HIGH-severity misconfigurations in a throwaway branch (no permanent repo changes)
  - Ensure neutral/failed behavior when `SNYK_TOKEN` is missing according to policy
  - _Requirements: 1.4, 2.2, 3.5, 6.1–6.3_
  - AC Validation: `workflow_dispatch` inputs `force_*` allow forcing jobs; Trivy/Snyk fail on HIGH/CRITICAL; Snyk guards handle missing token with enforced/skip modes.

Notes for implementers:
- Use matrices to iterate Terraform directories; generate the matrix JSON via shell and `fromJson` to avoid hard-coding paths.
- Keep runs on `ubuntu-latest` for consistent tool availability and performance.
- Prefer minimal logs; surface results via SARIF and summaries.