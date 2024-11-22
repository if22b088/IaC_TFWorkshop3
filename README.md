https://github.com/if22b088/IaC_TFWorkshop3


# Why do we need Terraform Cloud (or another backend) when we use CI/CD?

Terraform stores the configuration and managed infrastructure in the so called 'state'. The state is used to decide which changes are to be made to the infrastrucutre - i.e. what changed since the last apply. This is necessary but also increases performance because Terraform does not have to query each object/resource in the cloud to get its state (can take some time in large infrastructures).
The Terraform Cloud is used to store the 'state' remotely (in the cloud) so it can be shared with collaborators. Otherwise it would be stored locally on the workstation -> only one person has access to it and could not be used for github workflows.

# Automate Terraform with GitHub Actions

This repo is a companion repo to the [Automate Terraform with GitHub Actions tutorial](https://developer.hashicorp.com/terraform/tutorials/automation/github-actions).
