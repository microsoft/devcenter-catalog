# ARM Deployments

This template folder contains a suite of templates deployed through Azure Resource Manager (ARM). ARM templates are currently in GA for Azure Deployment Environments, and available to deploy for all customers.

### What will be deployed?

You can deploy the following test templates to ADE:
- [Empty](./Empty/azuredeploy.json) Will deploy an empty environment, which implies generating a resource group for your environment, but with no resources.
- [FunctionApp](./FunctionApp/azuredeploy.json) Will deploy a Function App, a Storage Account, and Application Insights resource.
- [FunctionApp With Parameters](./FunctionAppParameters/azuredeploy.json) Will deploy the same resources as the FunctionApp template, but allows a user to input the name and region for the Function App and related resources to be deployed in.
- [KeyVault](./KeyVault/azuredeploy.json) Will deploy a KeyVault resource.
- [StorageAccount](./StorageAccount/azuredeploy.json) Will deploy a Storage Account resource.
- [WebApp](./WebApp/azuredeploy.json) Will deploy a Web App resource.

### Learn more about ARM

- 📘 [ARM Template Documentation](https://learn.microsoft.com/en-us/azure/azure-resource-manager/templates/)
- 📘 [ARM Template Best Practices](https://learn.microsoft.com/en-us/azure/azure-resource-manager/templates/best-practices)
- 📘 [Understand Structure and Syntax of ARM Templates](https://learn.microsoft.com/en-us/azure/azure-resource-manager/templates/syntax)
