<!-- BEGIN_TF_DOCS -->
# Deployment Configuration

Environment-specific deployment configuration for GitHub Actions runners.
Orchestrates the main module with GitHub App credentials and repository webhooks.

## Features
* Workspace-based environment management
* GitHub App authentication via SSM parameters
* Repository webhook configuration

## Inputs

No inputs.

## Outputs

No outputs.

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_main"></a> [main](#module\_main) | ./.. | n/a |

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 6.27.0 |
| <a name="requirement_docker"></a> [docker](#requirement\_docker) | ~> 3.0 |
| <a name="requirement_github"></a> [github](#requirement\_github) | ~> 6.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.27.0 |
<!-- END_TF_DOCS -->