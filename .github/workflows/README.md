# Deploy Azure Monitor Workbooks with GitHub Actions + Terraform

This repository includes a reusable workflow to deploy the Workbooks using Terraform. The workflow file is located at:
- .github/workflows/deploy-workbooks.yml

## What the workflow does

- Authenticates to Azure using GitHub OIDC (no client secret needed).
- Runs `terraform init`, `validate`, `plan`, and `apply` using the example at `terraform/examples/single_rg`.
- Creates or updates the Azure Monitor Workbooks defined by the module.

## Prerequisites

- An Azure Subscription with:
  - A target Resource Group where workbooks will be created.
  - Two Log Analytics Workspaces (LAWs) that you will reference by name/RG.
- Permissions you will assign to an Azure Entra ID app registration (below).

## Configure Azure OIDC (recommended)

1) Create or select an app registration in Azure Entra ID.
2) Add a Federated Credential:
   - Issuer: `https://token.actions.githubusercontent.com`
   - Subject: `repo:OWNER/REPO:ref:refs/heads/main` (adjust branch as needed)  
     - For example, use your default branch or restrict to a specific branch.
   - Audience: `api://AzureADTokenExchange`
3) Assign RBAC to the app’s Service Principal:
   - Contributor on the target Resource Group (where workbooks will be created).
   - Reader on the Log Analytics Workspaces you reference (recommended for validation).
4) Collect the following values:
   - Tenant ID
   - Subscription ID
   - Client ID (of the app registration)

## Set GitHub repository variables

Add these as Repository Variables (not Secrets) so the workflow can log in with OIDC:

- AZURE_TENANT_ID = <your Azure Tenant ID>
- AZURE_SUBSCRIPTION_ID = <your Azure Subscription ID>
- AZURE_CLIENT_ID = <the App Registration Client ID>

GitHub UI path:
- Settings → Secrets and variables → Actions → Variables → New repository variable

The workflow reads them as `vars.*` and maps to Terraform via environment variables.

## Triggering a deployment

Manually run the workflow:

- GitHub → Actions → Deploy Azure Monitor Workbooks (Terraform) → Run workflow
- Provide inputs:
  - resource_group_name: Target RG for workbooks
  - location: Azure region (e.g., `eastus`)
  - workspace1_name: Name of LAW #1
  - workspace1_rg: Resource Group of LAW #1
  - workspace2_name: Name of LAW #2
  - workspace2_rg: Resource Group of LAW #2
  - management_group_path: Optional (e.g., `/providers/Microsoft.Management/managementGroups/<mg>`)
  - tags: Optional JSON map, e.g. `{"env":"dev","owner":"sre"}`

## What Terraform code is used

- Example stack: `terraform/examples/single_rg`
- Module: `terraform/modules/workbooks`
- Workbook templates: `workbooks/templates/`

Ensure the two LAWs exist and the Resource Group exists before running.

## Remote state (recommended)

This workflow runs in GitHub-hosted runners. For repeatable runs and proper drift detection, configure a remote backend (e.g., Azure Storage). You can add backend configuration to `terraform/examples/single_rg` and provide backend settings through environment variables or a backend config file. Without a remote backend, each run initializes a fresh local state, which is not persisted between runs.

## Permissions and scopes

- The OIDC app must have:
  - Contributor on the target RG for creating/updating workbooks.
  - Reader on referenced LAWs if you use data sources that read those resources.

## Troubleshooting

- Authorization errors:
  - Check that the Federated Credential issuer/subject/audience match the workflow’s repo and branch.
  - Confirm RBAC assignments and propagation (may take a few minutes).
- Variable issues:
  - Verify repository variables are set exactly as described.
  - Ensure `tags` input is valid JSON (quoted keys and string values).
- Resource conflicts:
  - If names already exist, Terraform may need the prior state or you should import the resource or align names to avoid duplicates.

## Files of interest

- Workflow: .github/workflows/deploy-workbooks.yml
- Example: terraform/examples/single_rg
- Module: terraform/modules/workbooks
- Workbooks templates: workbooks/templates
