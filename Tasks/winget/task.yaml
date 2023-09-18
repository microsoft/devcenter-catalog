# This is a winget package installation task for Dev Box.

name: winget
description: Applies a winget configuration to the Dev Box.
author: Microsoft Corporation
command: './main.ps1 -ConfigurationFile {{configurationFile}} -DownloadUrl {{downloadUrl}} -Package {{package}} -RunAsUser {{runAsUser}}'
inputs:
  configurationFile:
    defaultValue: ''
    type: 'string'
    required: false
    description: | 
      The path to the winget config yaml file. The file must be located in the local machine. 
  downloadUrl:
    defaultValue: ''
    type: 'string'
    required: false
    description: | 
      A publicly accessible URL where the config yaml file is stored. This file will be downloaded to the path given in 'configurationFile'.
  package:
    defaultValue: ''
    type: 'string'
    required: false
    description: |
      The name of the package to install. This is an alternative way. 
      If a config yaml file is provided under other parameters, there is no need for the package name.
  runAsUser:
    defaultValue: false
    type: 'boolean'
    required: false
    description: | 
      Whether to run the installation as the current user or as an administrator. 
      If set to true, the installation will run during the user's first login to the machine.
documentation:
  notes: This task allows installing packages via winget, or applying a winget configuration file.
  examples:
    - task: winget
      description: Install a package via winget
      inputs:
        package: git
    - task: winget
      description: Apply a winget configuration file that's already present on the machine
      inputs:
        configurationFile: 'C:\WinGetConfig\winget.yaml'
    - task: winget
      description: Apply a winget configuration file, downloading from a public URL to the specified path, running as the user
      inputs:
        downloadUrl: 'https://raw.githubusercontent.com/microsoft/devhome/main/sampleConfigurations/microsoft/vscode/configuration.dsc.yaml'
        configurationFile: 'C:\WinGetConfig\configuration.dsc.yaml'
        runAsUser: true
