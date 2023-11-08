# ARM Deployments

This template folder contains a suite of templates deployed through Azure Resource Manager (ARM). ARM templates are currently in GA for Azure Deployment Environments, and available to deploy for all customers.

### What will be deployed?

You can deploy the following test templates to ADE:
- [Sandbox](./Sandbox/azuredeploy.json) Will deploy an empty environment, which implies generating a resource group for your environment, but with no resources.
- [WebApp](./WebApp/azuredeploy.json) Will deploy an environment to host a Web App.

### Learn more about ARM

- 📘 [ARM Template Documentation](https://learn.microsoft.com/en-us/azure/azure-resource-manager/templates/)
- 📘 [ARM Template Best Practices](https://learn.microsoft.com/en-us/azure/azure-resource-manager/templates/best-practices)
- 📘 [Understand Structure and Syntax of ARM Templates](https://learn.microsoft.com/en-us/azure/azure-resource-manager/templates/syntax)
