@description('Prefix for resources deployed by this solution (App Service, Function App, monitoring, etc)')
param prefixName string = 'hdssdk${uniqueString(resourceGroup().id)}'

@description('Do you want to create a new Azure Health Data Services workspace or use an existing one?')
param createWorkspace bool

@description('Do you want to create a new FHIR Service or use an existing one?')
param createFhirService bool

@description('Name of Azure Health Data Services workspace to deploy or use.')
param workspaceName string

@description('Name of the FHIR service to deloy or use.')
param fhirServiceName string

@description('Name of the Log Analytics workspace to deploy or use. Leave blank to skip deployment')
param logAnalyticsName string = '${prefixName}-la'

@description('Location to deploy resources')
param location string = resourceGroup().location

@description('Location to deploy resources')
param appTags object = {}

@description('ID of principals to give FHIR Contributor on the FHIR service')
param fhirContributorPrincipals array = []

@description('Any custom function app settings')
param functionAppCustomSettings object = {}

@description('Tenant ID where resources are deployed')
var tenantId  = subscription().tenantId

@description('Deploy Azure Health Data Services and FHIR service')
module fhir './fhir.bicep'= {
  name: 'fhirDeploy'
  params: {
    createWorkspace: createWorkspace
    createFhirService: createFhirService
    workspaceName: workspaceName
    fhirServiceName: fhirServiceName
    location: location
    tenantId: tenantId
    appTags: appTags
  }
}

@description('Name for app insights resource used to monitor the Function App')
var appInsightsName = '${prefixName}-appins'

@description('Deploy monitoring and logging')
module monitoring './monitoring.bicep'= {
  name: 'monitoringDeploy'
  params: {
    logAnalyticsName: logAnalyticsName
    appInsightsName: appInsightsName
    location: location
    appTags: appTags
  }
}

@description('Name for the App Service used to host the Function App.')
var appServiceName = '${prefixName}-appserv'

@description('Name for the Function App to deploy the SDK custom operations to.')
var functionAppName = '${prefixName}-func'

@description('Name for the storage account needed for the Function App')
var funcStorName = '${replace(prefixName, '-', '')}funcsa'

@description('Deploy Azure Function to run SDK custom operations')
module function './azureFunction.bicep'= {
  name: 'functionDeploy'
  params: {
    appServiceName: appServiceName
    functionAppName: functionAppName
    storageAccountName: funcStorName
    location: location
    appInsightsInstrumentationKey: monitoring.outputs.appInsightsInstrumentationKey
    functionSettings: union({
      AZURE_FhirServerUrl: 'https://${workspaceName}-${fhirServiceName}.fhir.azurehealthcareapis.com'
      AZURE_InstrumentationKey: monitoring.outputs.appInsightsInstrumentationString
    }, functionAppCustomSettings)
    appTags: appTags
  }
}

@description('Setup identity connection between FHIR and the function app')
module functionFhirIdentity './fhirIdentity.bicep'= {
  name: 'fhirIdentity-function'
  params: {
    fhirId: fhir.outputs.fhirId
    principalId: function.outputs.functionAppPrincipalId
  }
}

@description('Setup identity connection between FHIR and the function app')
module specifiedIdentity './fhirIdentity.bicep' =  [for principalId in  fhirContributorPrincipals: {
  name: 'fhirIdentity-${principalId}'
  params: {
    fhirId: fhir.outputs.fhirId
    principalId: principalId
    principalType: 'User'
  }
}]

output FhirServiceId string = fhir.outputs.fhirId
output FhirServiceUrl string = 'https://${workspaceName}-${fhirServiceName}.fhir.azurehealthcareapis.com'
