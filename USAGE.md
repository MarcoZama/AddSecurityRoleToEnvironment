# Usage Examples

## Service Principal Authentication (Recommended for Automation)

```powershell
# Example with all required parameters
.\Create-DeveloperSecurityRole.ps1 -UseServicePrincipal `
  -TenantId "your-tenant-id" `
  -ClientId "your-client-id" `
  -ClientSecret "your-client-secret" `
  -EnvironmentId "your-env-id"

# Example with custom role name and description
.\Create-DeveloperSecurityRole.ps1 -UseServicePrincipal `
  -TenantId "your-tenant-id" `
  -ClientId "your-client-id" `
  -ClientSecret "your-client-secret" `
  -EnvironmentId "your-environment-id" `
  -RoleName "CustomDeveloper" `
  -RoleDescription "Custom developer role with restricted permissions"
```

## User Authentication (Interactive)

```powershell
# Connect to Azure first
Connect-AzAccount

# Run with Environment ID only
.\Create-DeveloperSecurityRole.ps1 -EnvironmentId "your-env-id"

# Run with Environment URL only
.\Create-DeveloperSecurityRole.ps1 -EnvironmentUrl "your-env-url"

# Run with both ID and URL for validation
.\Create-DeveloperSecurityRole.ps1 `
  -EnvironmentId "your-env-id" `
  -EnvironmentUrl "your-env-url"
```

## Parameter Reference

| Parameter | Required | Description |
|-----------|----------|-------------|
| EnvironmentId | Conditional | Power Platform environment ID (GUID) |
| EnvironmentUrl | Conditional | Dataverse environment URL |
| RoleName | Optional | Name of the security role (default: "Developer") |
| RoleDescription | Optional | Description of the role |
| UseServicePrincipal | Optional | Switch to use Service Principal authentication |
| TenantId | Conditional | Azure AD tenant ID (required with Service Principal) |
| ClientId | Conditional | App registration client ID (required with Service Principal) |
| ClientSecret | Conditional | App registration client secret (required with Service Principal) |

**Note**: Either EnvironmentId or EnvironmentUrl (or both) must be provided.

## Common Scenarios

### CI/CD Pipeline
Use Service Principal authentication for automated deployments:
```powershell
# Store secrets in Azure Key Vault or pipeline variables
$TenantId = $env:AZURE_TENANT_ID
$ClientId = $env:AZURE_CLIENT_ID  
$ClientSecret = $env:AZURE_CLIENT_SECRET
$EnvironmentId = $env:POWERPLATFORM_ENV_ID

.\Create-DeveloperSecurityRole.ps1 -UseServicePrincipal `
  -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret `
  -EnvironmentId $EnvironmentId
```

### Development Environment Setup
Quick setup for development environments:
```powershell
# Interactive authentication
Connect-AzAccount
.\Create-DeveloperSecurityRole.ps1 -EnvironmentId "your-dev-env-id"
```

### Multiple Environments
Deploy to multiple environments:
```powershell
$environments = @(
    "dev-environment-id",
    "test-environment-id", 
    "staging-environment-id"
)

foreach ($envId in $environments) {
    Write-Host "Creating role in environment: $envId"
    .\Create-DeveloperSecurityRole.ps1 -UseServicePrincipal `
      -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret `
      -EnvironmentId $envId -RoleName "Developer-$envId"
}
```

## Error Handling

The script provides detailed error messages and fallback options:
- Authentication failures include troubleshooting steps
- API failures fall back to manual creation instructions
- Service Principal issues provide setup guidance
- Token acquisition errors include verification steps

## Security Notes

- Never commit client secrets to source control
- Use Azure Key Vault for secret storage in production
- Rotate client secrets regularly
- Monitor Service Principal usage through Azure AD audit logs
- Consider using managed identities where possible
