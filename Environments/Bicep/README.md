# Bicep Deployments

This template folder contains a suite of templates deployed through Bicep, a declarative language developed by Microsoft to deploy Azure Resources as an alternative to ARM JSON-based templates. Deploying Bicep templates is currently a private-preview feature for Azure Deployment Environnments.

### What will be deployed?

You can deploy the following test templates to ADE:
[AppConfig](./AppConfig/appconfig.bicep) Deploys an App Configuration resource.
[LinkedTemplate](./LinkedTemplate/main.bicep) Offers an example of using Linked Bicep templates for ADE, where the template deploys and App Configuration resource and a Storage Account.

### Learn more about Bicep

- 📘 [Bicep Template Documentation](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
- 📘 [Bicep Template Best Practices](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/best-practices)
- 📘 [Understand Structure and Syntax of Bicep Templates](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/file)