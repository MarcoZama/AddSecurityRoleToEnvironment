# Service Principal Setup Guide for Dataverse API Access

This guide explains how to set up a Service Principal (App Registration) to programmatically create security roles in Power Platform using the `Create-DeveloperSecurityRole.ps1` script.

## Prerequisites

- Azure AD Global Administrator or Application Administrator role
- Power Platform Administrator role
- Access to Azure Portal and Power Platform Admin Center

## Step 1: Create App Registration in Azure AD

1. **Navigate to Azure Portal**
   - Go to [Azure Portal](https://portal.azure.com)
   - Navigate to **Azure Active Directory** > **App registrations**

2. **Create New Registration**
   - Click **"New registration"**
   - **Name**: `PowerPlatform-SecurityRole-Creator`
   - **Supported account types**: `Accounts in this organizational directory only`
   - **Redirect URI**: Leave blank
   - Click **"Register"**

3. **Copy Important Values**
   - Copy the **Application (client) ID**
   - Copy the **Directory (tenant) ID**
   - You'll need these for the script

## Step 2: Create Client Secret

1. **Navigate to Certificates & Secrets**
   - In your app registration, go to **"Certificates & secrets"**
   - Click **"New client secret"**

2. **Configure Secret**
   - **Description**: `Dataverse API Access`
   - **Expires**: Choose appropriate duration (recommend 12-24 months)
   - Click **"Add"**

3. **Copy Secret Value**
   - **IMPORTANT**: Copy the secret **Value** immediately
   - You won't be able to see it again after leaving this page
   - Store it securely (consider using Azure Key Vault)

## Step 3: Configure API Permissions

1. **Add Dynamics CRM Permission**
   - Go to **"API permissions"**
   - Click **"Add a permission"**
   - Select **"Dynamics CRM"**
   - Choose **"Delegated permissions"**
   - Check **"user_impersonation"**
   - Click **"Add permissions"**

2. **Grant Admin Consent**
   - Click **"Grant admin consent for [Your Organization]"**
   - Click **"Yes"** to confirm
   - Verify the status shows green checkmarks

## Step 4: Add Service Principal to Power Platform

1. **Navigate to Power Platform Admin Center**
   - Go to [Power Platform Admin Center](https://admin.powerplatform.microsoft.com)
   - Navigate to your target environment

2. **Add Application User**
   - Go to **Settings** > **Users + permissions** > **Application users**
   - Click **"New app user"**

3. **Configure Application User**
   - **App**: Select your app registration (`PowerPlatform-SecurityRole-Creator`)
   - **Business unit**: Select the root business unit
   - **Security roles**: Assign **"System Administrator"** role
   - Click **"Create"**

## Step 5: Run Script with Service Principal

Once setup is complete, run the script with Service Principal authentication:

```powershell
.\Create-DeveloperSecurityRole.ps1 -UseServicePrincipal `
  -TenantId "your-tenant-id" `
  -ClientId "your-app-registration-client-id" `
  -ClientSecret "your-client-secret" `
  -EnvironmentId "your-environment-id"
```

### Parameter Values:
- **TenantId**: Directory (tenant) ID from Step 1
- **ClientId**: Application (client) ID from Step 1  
- **ClientSecret**: Secret value from Step 2
- **EnvironmentId**: Power Platform environment ID

## Security Best Practices

### Secret Management
- Store secrets in Azure Key Vault or similar secure storage
- Use environment variables instead of hardcoding secrets
- Rotate secrets regularly based on your organization's policy

### Permissions
- The Service Principal gets System Administrator role for API access
- This is required for creating security roles via Dataverse API
- Consider creating a custom role with minimal required permissions

### Monitoring
- Monitor the Service Principal usage in Azure AD audit logs
- Set up alerts for unusual activity
- Review and audit permissions regularly

## Troubleshooting

### Common Issues

**401 Unauthorized**
- Verify the Service Principal has System Administrator role in the environment
- Check that admin consent was granted for API permissions
- Ensure client secret hasn't expired

**403 Forbidden**
- Service Principal may not have sufficient privileges
- Verify the app user was created correctly in Power Platform
- Check that the correct security role is assigned

**Token Acquisition Failed**
- Verify TenantId, ClientId, and ClientSecret are correct
- Check that the app registration is in the correct Azure AD tenant
- Ensure client secret is not expired

### Verification Steps

1. **Check App Registration**
   ```powershell
   # Verify app exists
   Get-AzADApplication -DisplayName "PowerPlatform-SecurityRole-Creator"
   ```

2. **Test Token Acquisition**
   ```powershell
   # Test if token can be obtained
   $tokenEndpoint = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"
   # Use your actual values to test
   ```

3. **Verify Environment Access**
   - Check that the environment ID is correct
   - Ensure the Service Principal is listed in Application users
   - Verify System Administrator role is assigned

## Alternative Approaches

If Service Principal setup is complex for your organization, consider:

1. **Manual Role Creation**: Use the script's manual fallback instructions
2. **PowerShell with User Auth**: Run script with interactive user authentication
3. **Azure DevOps Service Connections**: For CI/CD scenarios

## Security Considerations

- The System Administrator role grants broad permissions
- Consider using this Service Principal only for role creation tasks
- Implement proper access controls and monitoring
- Follow your organization's identity governance policies

## Script Features

### Developer Security Role Capabilities
The script creates a role with these permissions:
- Canvas App creation and management
- Model-driven App creation and management
- Power Automate Flow creation and management
- Copilot Studio Agent and Chatbot creation
- AI Builder Model creation and usage
- Read/Write access to existing tables (Account, Contact, etc.)
- Solution packaging capabilities

### Restricted Capabilities
The role explicitly excludes these permissions:
- Custom table creation
- Field/column creation
- Relationship modification
- System-level customizations
- Metadata modification

### Authentication Methods
1. **Service Principal Authentication**: For automation and CI/CD
2. **User Authentication**: For interactive use

### Error Handling
- Comprehensive error messages
- Fallback to manual creation steps
- Service Principal troubleshooting guidance
- Token acquisition error handling

---

**Next Steps**: After successful setup, you can programmatically create security roles using the enhanced script with Service Principal authentication.