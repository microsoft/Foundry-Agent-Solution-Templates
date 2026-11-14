// Returns the image azd last deployed, so re-provisioning does not reset the app to the placeholder.
// A separate module, because a resource cannot read its own current state while it is being deployed.
param name string
param exists bool

resource app 'Microsoft.App/containerApps@2024-03-01' existing = if (exists) {
  name: name
}

output image string = exists ? app!.properties.template.containers[0].image : 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'
