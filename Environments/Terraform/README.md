# Terraform Deployments

This template folder contains a suite of templates deployed through Terraform. Deploying Terraform templates is currently a private-preview feature for Azure Deployment Environments.

### What will be deployed?

You can deploy the following test templates to ADE:
- [Azure Data Labs - Azure ML](./AzureDataLabs_AzureML/infra/main.tf) In partnership with Azure Data Labs, this template will deploy all the resources necessary to deploy an Azure ML environment. Please refer to the definition's README for additional details.
- [Azure Data Labs - Azure Synapse](./AzureDataLabs_AzureSynapse/infra/main.tf) In partnership with Azure Data Labs, this template will deploy all the resources necessary to utilize Azure Synapse. Please refer to the definition's README for additional details.
- [FunctionApp](./FunctionApp/function_app.tf) Will deploy a Function App resource.
- [Sandbox](./Sandbox/empty.tf) Will deploy a sandbox (empty) environment.
- [VNET](./VNET/main.tf) Will deploy a Virtual Network resource.
- [WebApp](./WebApp/web_app.tf) Will deploy a Web App resource.

### Learn more about Terraform

- 📘 [Terraform Documentation](https://developer.hashicorp.com/terraform/docs)
- 📘 [Terraform Configuration Language Docs](https://developer.hashicorp.com/terraform/language)