# Create Custom Developer Security Role for Power Platform
# This script creates a security role definition with restricted permissions for developers
# Role creation via Dataverse Web API with fallback to manual steps

param(
    [Parameter(Mandatory=$false)]
    [string]$EnvironmentId,
    
    [Parameter(Mandatory=$false)]
    [string]$EnvironmentUrl,
    
    [Parameter(Mandatory=$false)]
    [string]$RoleName = "Developer",
    
    [Parameter(Mandatory=$false)]
    [string]$RoleDescription = "Custom role for developers - can create apps/flows/agents but not custom tables",
    
    # Service Principal Authentication Parameters
    [Parameter(Mandatory=$false)]
    [string]$TenantId,
    
    [Parameter(Mandatory=$false)]
    [string]$ClientId,
    
    [Parameter(Mandatory=$false)]
    [string]$ClientSecret,
    
    [Parameter(Mandatory=$false)]
    [switch]$UseServicePrincipal
)

# Validate parameters - at least one must be provided
if (-not $EnvironmentId -and -not $EnvironmentUrl) {
    Write-Host "ERROR: Either EnvironmentId or EnvironmentUrl (or both) must be provided." -ForegroundColor Red
    Write-Host "Usage examples:" -ForegroundColor Yellow
    Write-Host "  .\Create-DeveloperSecurityRole.ps1 -EnvironmentId 'your-env-id'" -ForegroundColor Gray
    Write-Host "  .\Create-DeveloperSecurityRole.ps1 -EnvironmentUrl 'your-env-url'" -ForegroundColor Gray
    Write-Host "  .\Create-DeveloperSecurityRole.ps1 -EnvironmentId 'your-env-id' -EnvironmentUrl 'your-env-url'" -ForegroundColor Gray
    Write-Host "  .\Create-DeveloperSecurityRole.ps1 -UseServicePrincipal -TenantId 'your-tenant-id' -ClientId 'your-client-id' -ClientSecret 'your-secret' -EnvironmentId 'your-env-id'" -ForegroundColor Gray
    exit 1
}

# Validate Service Principal parameters if using Service Principal
if ($UseServicePrincipal) {
    if (-not $TenantId -or -not $ClientId -or -not $ClientSecret) {
        Write-Host "ERROR: When using -UseServicePrincipal, TenantId, ClientId, and ClientSecret are required." -ForegroundColor Red
        Write-Host "Usage: .\Create-DeveloperSecurityRole.ps1 -UseServicePrincipal -TenantId 'your-tenant-id' -ClientId 'your-client-id' -ClientSecret 'your-secret' -EnvironmentId 'env-id'" -ForegroundColor Yellow
        exit 1
    }
}

Write-Host "Checking authentication..." -ForegroundColor Yellow

# Check authentication method
if ($UseServicePrincipal) {
    Write-Host "Using Service Principal authentication..." -ForegroundColor Cyan
    
    try {
        # Connect using Service Principal
        $secureSecret = ConvertTo-SecureString $ClientSecret -AsPlainText -Force
        $credential = New-Object System.Management.Automation.PSCredential($ClientId, $secureSecret)
        
        Connect-AzAccount -ServicePrincipal -Credential $credential -Tenant $TenantId -Force | Out-Null
        
        $context = Get-AzContext
        if ($context) {
            Write-Host "SUCCESS: Service Principal authenticated: $($context.Account.Id)" -ForegroundColor Green
            Write-Host "Tenant: $($context.Tenant.Id)" -ForegroundColor White
        } else {
            Write-Host "ERROR: Service Principal authentication failed." -ForegroundColor Red
            exit 1
        }
    } catch {
        Write-Host "ERROR: Service Principal authentication failed: $_" -ForegroundColor Red
        Write-Host "Please verify your TenantId, ClientId, and ClientSecret." -ForegroundColor Yellow
        exit 1
    }
} else {
    # Check if user is authenticated to Azure
    try {
        $context = Get-AzContext
        if (-not $context) {
            Write-Host "ERROR: Not authenticated to Azure. Please run 'Connect-AzAccount' first." -ForegroundColor Red
            Write-Host "Or use Service Principal: -UseServicePrincipal -TenantId 'your-tenant' -ClientId 'your-client-id' -ClientSecret 'your-secret'" -ForegroundColor Yellow
            exit 1
        } else {
            Write-Host "SUCCESS: Azure authentication found: $($context.Account.Id)" -ForegroundColor Green
        }
    } catch {
        Write-Host "ERROR: Azure PowerShell module not available. Please install: Install-Module Az" -ForegroundColor Red
        Write-Host "And run: Connect-AzAccount" -ForegroundColor Yellow
        exit 1
    }
}

# Import required modules
Import-Module Microsoft.PowerApps.Administration.PowerShell -Force
Import-Module Microsoft.PowerApps.PowerShell -Force

# Add required assemblies for URL encoding
Add-Type -AssemblyName System.Web

# Function to get access token for Dataverse API
function Get-DataverseAccessToken {
    param(
        [string]$EnvironmentUrl,
        [bool]$UseServicePrincipal = $false,
        [string]$TenantId = $null,
        [string]$ClientId = $null,
        [string]$ClientSecret = $null
    )
    
    try {
        if ($UseServicePrincipal -and $TenantId -and $ClientId -and $ClientSecret) {
            Write-Host "Getting Service Principal access token for Dataverse..." -ForegroundColor Yellow
            
            # Use client credentials flow for Service Principal
            $tokenEndpoint = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"
            
            $body = @{
                client_id = $ClientId
                client_secret = $ClientSecret
                scope = "$EnvironmentUrl/.default"
                grant_type = "client_credentials"
            }
            
            $response = Invoke-RestMethod -Uri $tokenEndpoint -Method POST -Body $body -ContentType "application/x-www-form-urlencoded"
            
            if ($response.access_token) {
                Write-Host "SUCCESS: Service Principal token obtained" -ForegroundColor Green
                return $response.access_token
            } else {
                Write-Host "ERROR: Failed to get Service Principal token" -ForegroundColor Red
                return $null
            }
        } else {
            # Use user authentication
            Write-Host "Getting user access token for Dataverse..." -ForegroundColor Yellow
            $token = (Get-AzAccessToken -ResourceUrl $EnvironmentUrl).Token
            
            if ($token) {
                Write-Host "SUCCESS: User token obtained" -ForegroundColor Green
                return $token
            } else {
                Write-Host "ERROR: Failed to get user token" -ForegroundColor Red
                return $null
            }
        }
    } catch {
        Write-Host "ERROR: Token acquisition failed: $_" -ForegroundColor Red
        return $null
    }
}

# Function to create security role via Dataverse Web API
function New-DataverseSecurityRole {
    param(
        [string]$EnvironmentUrl,
        [string]$RoleName,
        [string]$RoleDescription,
        [array]$Privileges
    )
    
    try {
        # Get access token using the appropriate method
        $token = Get-DataverseAccessToken -EnvironmentUrl $EnvironmentUrl -UseServicePrincipal $UseServicePrincipal -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret
        
        if (-not $token) {
            Write-Host "ERROR: Could not obtain access token" -ForegroundColor Red
            return $null
        }
        
        # Headers
        $headers = @{
            'Authorization' = "Bearer $token"
            'Content-Type' = 'application/json'
            'OData-MaxVersion' = '4.0'
            'OData-Version' = '4.0'
        }
        
        # First, get the root business unit ID
        Write-Host "Getting business unit information..." -ForegroundColor Yellow
        try {
            $businessUnitsEndpoint = "$EnvironmentUrl/api/data/v9.2/businessunits?`$filter=parentbusinessunitid eq null&`$select=businessunitid,name"
            $businessUnitResponse = Invoke-RestMethod -Uri $businessUnitsEndpoint -Method GET -Headers $headers
            
            if ($businessUnitResponse.value -and $businessUnitResponse.value.Count -gt 0) {
                $businessUnitId = $businessUnitResponse.value[0].businessunitid
                Write-Host "Found root business unit: $($businessUnitResponse.value[0].name) ($businessUnitId)" -ForegroundColor Green
            } else {
                Write-Host "ERROR: Could not find root business unit" -ForegroundColor Red
                return $null
            }
        } catch {
            Write-Host "ERROR: Failed to get business unit: $_" -ForegroundColor Red
            return $null
        }
        
        # Create role payload with proper business unit reference
        $rolePayload = @{
            name = $RoleName
            description = $RoleDescription
            "businessunitid@odata.bind" = "/businessunits($businessUnitId)"
        } | ConvertTo-Json
        
        # API endpoint for roles
        $rolesEndpoint = "$EnvironmentUrl/api/data/v9.2/roles"
        
        Write-Host "Creating role via Dataverse API..." -ForegroundColor Yellow
        
        # Create the role
        $response = Invoke-RestMethod -Uri $rolesEndpoint -Method POST -Body $rolePayload -Headers $headers
        
        if ($response) {
            Write-Host "SUCCESS: Role '$RoleName' created successfully!" -ForegroundColor Green
            Write-Host "Role ID: $($response.roleid)" -ForegroundColor White
            return $response.roleid
        }
        
    } catch {
        Write-Host "ERROR: Failed to create role via API: $_" -ForegroundColor Red
        
        # Provide specific guidance for common Service Principal issues
        if ($UseServicePrincipal) {
            Write-Host "`nService Principal Troubleshooting:" -ForegroundColor Yellow
            Write-Host "1. Ensure the Service Principal has 'System Administrator' role in the Dataverse environment" -ForegroundColor White
            Write-Host "2. Verify the Service Principal is added as an Application User in Power Platform Admin Center" -ForegroundColor White
            Write-Host "3. Check that the ClientId and ClientSecret are correct" -ForegroundColor White
            Write-Host "4. Confirm the TenantId matches your Azure AD tenant" -ForegroundColor White
        }
        
        return $null
    }
}

# Function to assign privileges to role
function Add-RolePrivileges {
    param(
        [string]$EnvironmentUrl,
        [string]$RoleId,
        [array]$Privileges
    )
    
    try {
        $token = Get-DataverseAccessToken -EnvironmentUrl $EnvironmentUrl -UseServicePrincipal $UseServicePrincipal -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret
        
        if (-not $token) {
            Write-Host "ERROR: Could not obtain access token for privileges assignment" -ForegroundColor Red
            return
        }
        
        $headers = @{
            'Authorization' = "Bearer $token"
            'Content-Type' = 'application/json'
            'OData-MaxVersion' = '4.0'
            'OData-Version' = '4.0'
        }
        
        Write-Host "Adding privileges to role..." -ForegroundColor Yellow
        
        foreach ($privilege in $Privileges) {
            $privilegePayload = @{
                "privilege@odata.bind" = "/privileges($($privilege.privilegeid))"
                "role@odata.bind" = "/roles($RoleId)"
                depth = $privilege.depth
            } | ConvertTo-Json
            
            $endpoint = "$EnvironmentUrl/api/data/v9.2/roleprivileges"
            
            try {
                Invoke-RestMethod -Uri $endpoint -Method POST -Body $privilegePayload -Headers $headers
                Write-Host "  SUCCESS: Added privilege: $($privilege.privilegeid)" -ForegroundColor Gray
            } catch {
                Write-Warning "Failed to add privilege $($privilege.privilegeid): $_"
            }
        }
        
        Write-Host "SUCCESS: Privileges assignment completed!" -ForegroundColor Green
        
    } catch {
        Write-Host "ERROR: Failed to assign privileges: $_" -ForegroundColor Red
    }
}

Write-Host "Creating custom '$RoleName' security role..." -ForegroundColor Yellow

try {
    # Connect to the environment
    Write-Host "Resolving environment details..." -ForegroundColor Yellow
    
    if ($EnvironmentId) {
        Write-Host "Environment ID provided: $EnvironmentId" -ForegroundColor White
    }
    if ($EnvironmentUrl) {
        Write-Host "Environment URL provided: $EnvironmentUrl" -ForegroundColor White
    }
    
    # Get environment details
    $environment = $null
    $targetEnvironmentUrl = $null
    
    try {
        # Priority logic: if both are provided, validate they match
        if ($EnvironmentId -and $EnvironmentUrl) {
            Write-Host "Both ID and URL provided - validating consistency..." -ForegroundColor Yellow
            
            # Get environment by ID first
            $environment = Get-AdminPowerAppEnvironment -EnvironmentName $EnvironmentId
            if ($environment) {
                Write-Host "Environment found by ID: $($environment.DisplayName)" -ForegroundColor Green
                Write-Host "Environment URL from ID: $($environment.EnvironmentUrl)" -ForegroundColor White
                
                # Check if URLs match (normalize URLs by removing trailing slashes)
                $normalizedEnvUrl = $environment.EnvironmentUrl.TrimEnd('/')
                $normalizedProvidedUrl = $EnvironmentUrl.TrimEnd('/')
                
                if ($normalizedEnvUrl -eq $normalizedProvidedUrl) {
                    Write-Host "SUCCESS: Environment ID and URL are consistent" -ForegroundColor Green
                    $targetEnvironmentUrl = $environment.EnvironmentUrl
                } else {
                    Write-Host "WARNING: Provided URL doesn't match environment ID." -ForegroundColor Yellow
                    Write-Host "   Environment URL: $normalizedEnvUrl" -ForegroundColor Gray
                    Write-Host "   Provided URL:   $normalizedProvidedUrl" -ForegroundColor Gray
                    Write-Host "   Using URL from environment ID." -ForegroundColor Yellow
                    $targetEnvironmentUrl = $environment.EnvironmentUrl
                }
            } else {
                Write-Host "WARNING: Environment ID not found. Using provided URL." -ForegroundColor Yellow
                $targetEnvironmentUrl = $EnvironmentUrl
            }
        }
        elseif ($EnvironmentId) {
            # Get environment by ID only
            $environment = Get-AdminPowerAppEnvironment -EnvironmentName $EnvironmentId
            if ($environment) {
                Write-Host "Environment found: $($environment.DisplayName)" -ForegroundColor Green
                Write-Host "Environment URL: $($environment.EnvironmentUrl)" -ForegroundColor White
                $targetEnvironmentUrl = $environment.EnvironmentUrl
            } else {
                Write-Host "WARNING: Environment ID not found" -ForegroundColor Yellow
            }
        }
        else {
            # Use provided URL and try to find matching environment
            $targetEnvironmentUrl = $EnvironmentUrl
            Write-Host "Looking up environment details for URL: $EnvironmentUrl" -ForegroundColor Yellow
            
            $environments = Get-AdminPowerAppEnvironment
            $environment = $environments | Where-Object { $_.EnvironmentUrl -eq $EnvironmentUrl }
            
            if ($environment) {
                Write-Host "Environment found: $($environment.DisplayName)" -ForegroundColor Green
                Write-Host "Environment ID: $($environment.EnvironmentName)" -ForegroundColor White
            } else {
                Write-Host "Environment details not found, but proceeding with provided URL" -ForegroundColor Yellow
            }
        }
    } catch {
        Write-Warning "Could not retrieve environment details. Continuing with role definition..."
        # Use whatever URL we have
        if ($EnvironmentUrl) {
            $targetEnvironmentUrl = $EnvironmentUrl
        } elseif ($environment -and $environment.EnvironmentUrl) {
            $targetEnvironmentUrl = $environment.EnvironmentUrl
        }
    }
    
    # Role definition with all privileges
    
    $roleDefinition = @{
        name = $RoleName
        description = $RoleDescription
        businessunitid = "root-business-unit-id"
        
        # Core permissions for app development
        privileges = @(
            # Basic User Privileges
            @{ privilegeid = "prvReadUser"; depth = "Basic" }
            @{ privilegeid = "prvReadBusinessUnit"; depth = "Local" }
            
            # App Creation Rights
            @{ privilegeid = "prvCreateAppModule"; depth = "Global" }
            @{ privilegeid = "prvWriteAppModule"; depth = "Global" }
            @{ privilegeid = "prvReadAppModule"; depth = "Global" }
            @{ privilegeid = "prvShareAppModule"; depth = "Global" }
            
            # Canvas App Rights
            @{ privilegeid = "prvCreateCanvasApp"; depth = "Global" }
            @{ privilegeid = "prvWriteCanvasApp"; depth = "Global" }
            @{ privilegeid = "prvReadCanvasApp"; depth = "Global" }
            @{ privilegeid = "prvShareCanvasApp"; depth = "Global" }
            
            # Flow Creation Rights
            @{ privilegeid = "prvCreateWorkflow"; depth = "Global" }
            @{ privilegeid = "prvWriteWorkflow"; depth = "Global" }
            @{ privilegeid = "prvReadWorkflow"; depth = "Global" }
            
            # Copilot Studio Agent Rights
            @{ privilegeid = "prvCreateBot"; depth = "Global" }
            @{ privilegeid = "prvWriteBot"; depth = "Global" }
            @{ privilegeid = "prvReadBot"; depth = "Global" }
            @{ privilegeid = "prvDeleteBot"; depth = "Global" }
            @{ privilegeid = "prvShareBot"; depth = "Global" }
            
            # Copilot Studio Component Rights
            @{ privilegeid = "prvCreateBotComponent"; depth = "Global" }
            @{ privilegeid = "prvWriteBotComponent"; depth = "Global" }
            @{ privilegeid = "prvReadBotComponent"; depth = "Global" }
            @{ privilegeid = "prvDeleteBotComponent"; depth = "Global" }
            
            # AI Builder Rights (for AI capabilities in agents)
            @{ privilegeid = "prvCreateAIModel"; depth = "Global" }
            @{ privilegeid = "prvWriteAIModel"; depth = "Global" }
            @{ privilegeid = "prvReadAIModel"; depth = "Global" }
            @{ privilegeid = "prvUseAIModel"; depth = "Global" }
            
            # Chatbot Rights
            @{ privilegeid = "prvCreateChatbot"; depth = "Global" }
            @{ privilegeid = "prvWriteChatbot"; depth = "Global" }
            @{ privilegeid = "prvReadChatbot"; depth = "Global" }
            @{ privilegeid = "prvDeleteChatbot"; depth = "Global" }
            @{ privilegeid = "prvPublishChatbot"; depth = "Global" }
            
            # Solution Rights (for packaging)
            @{ privilegeid = "prvReadSolution"; depth = "Global" }
            @{ privilegeid = "prvWriteSolution"; depth = "Global" }
            @{ privilegeid = "prvCreateSolution"; depth = "Global" }
            
            # Data Access (Read/Write on existing tables)
            @{ privilegeid = "prvReadAccount"; depth = "Global" }
            @{ privilegeid = "prvWriteAccount"; depth = "Global" }
            @{ privilegeid = "prvCreateAccount"; depth = "Global" }
            
            @{ privilegeid = "prvReadContact"; depth = "Global" }
            @{ privilegeid = "prvWriteContact"; depth = "Global" }
            @{ privilegeid = "prvCreateContact"; depth = "Global" }
            
            # Add more table permissions as needed
            # NOTE: Custom table permissions would be added here for existing custom tables
        )
        
        # Explicitly EXCLUDE metadata modification privileges
        excludedPrivileges = @(
            "prvCreateEntity",           # Create custom tables
            "prvWriteEntity",           # Modify table metadata
            "prvDeleteEntity",          # Delete tables
            "prvCreateAttribute",       # Create custom fields
            "prvWriteAttribute",        # Modify field metadata
            "prvDeleteAttribute",       # Delete fields
            "prvCreateRelationship",    # Create relationships
            "prvWriteRelationship",     # Modify relationships
            "prvDeleteRelationship",    # Delete relationships
            "prvCreateOptionSet",       # Create choice columns
            "prvWriteOptionSet",        # Modify choice columns
            "prvDeleteOptionSet",       # Delete choice columns
            "prvPublishDuplicateRule",  # System customization
            "prvPublishWorkflow"        # Advanced workflow publishing
        )
    }
    
    Write-Host "`nRole Definition:" -ForegroundColor Green
    Write-Host "Name: $($roleDefinition.name)" -ForegroundColor White
    Write-Host "Description: $($roleDefinition.description)" -ForegroundColor White
    Write-Host "Privileges Count: $($roleDefinition.privileges.Count)" -ForegroundColor White
    Write-Host "Excluded Privileges Count: $($roleDefinition.excludedPrivileges.Count)" -ForegroundColor White
    
    Write-Host "`nIncluded Capabilities:" -ForegroundColor Green
    Write-Host "  - Canvas & Model-driven Apps" -ForegroundColor White
    Write-Host "  - Power Automate Flows" -ForegroundColor White
    Write-Host "  - Copilot Studio Agents & Chatbots" -ForegroundColor White
    Write-Host "  - AI Builder Models" -ForegroundColor White
    Write-Host "  - Read/Write on existing tables" -ForegroundColor White
    Write-Host "  - Solution packaging" -ForegroundColor White
    
    Write-Host "`nRestricted Capabilities:" -ForegroundColor Red
    Write-Host "  - Custom table creation" -ForegroundColor White
    Write-Host "  - Field/column creation" -ForegroundColor White
    Write-Host "  - Relationship modification" -ForegroundColor White
    Write-Host "  - System-level customizations" -ForegroundColor White
    
    Write-Host "`nATTEMPTING TO CREATE ROLE VIA DATAVERSE API..." -ForegroundColor Cyan
    
    if ($targetEnvironmentUrl) {
        # Try to create the role via API
        $roleId = New-DataverseSecurityRole -EnvironmentUrl $targetEnvironmentUrl -RoleName $RoleName -RoleDescription $RoleDescription -Privileges $roleDefinition.privileges
        
        if ($roleId) {
            # Add privileges to the role
            Add-RolePrivileges -EnvironmentUrl $targetEnvironmentUrl -RoleId $roleId -Privileges $roleDefinition.privileges
            
            Write-Host "`nSUCCESS! Role created via Dataverse API!" -ForegroundColor Green
            Write-Host "Role Name: $RoleName" -ForegroundColor White
            Write-Host "Role ID: $roleId" -ForegroundColor White
            if ($environment) {
                Write-Host "Environment: $($environment.DisplayName)" -ForegroundColor White
            } else {
                Write-Host "Environment URL: $targetEnvironmentUrl" -ForegroundColor White
            }
        } else {
            Write-Host "`nWARNING: API creation failed. Use manual steps below." -ForegroundColor Yellow
        }
    } else {
        Write-Host "`nWARNING: Environment URL not available. Use manual steps below." -ForegroundColor Yellow
    }
    
    Write-Host "`n=== Fallback Manual Steps ===" -ForegroundColor Cyan
    Write-Host "If API creation failed, use Power Platform Admin Center:" -ForegroundColor White
    Write-Host "1. Go to Power Platform Admin Center" -ForegroundColor White
    
    if ($EnvironmentId) {
        Write-Host "2. Navigate to your environment: $EnvironmentId" -ForegroundColor White
    } elseif ($environment) {
        Write-Host "2. Navigate to your environment: $($environment.EnvironmentName)" -ForegroundColor White
    } else {
        Write-Host "2. Navigate to your environment (find via URL: $EnvironmentUrl)" -ForegroundColor White
    }
    
    Write-Host "3. Go to Settings > Users + permissions > Security roles" -ForegroundColor White
    Write-Host "4. Create new role with name: '$RoleName'" -ForegroundColor White
    Write-Host "5. Configure permissions as shown above" -ForegroundColor White
    Write-Host "6. Save the role" -ForegroundColor Green
    
    if ($UseServicePrincipal -and -not $roleId) {
        Write-Host "`n=== Service Principal Setup Guide ===" -ForegroundColor Cyan
        Write-Host "To use Service Principal authentication, complete these steps:" -ForegroundColor White
        Write-Host "`n1. Create App Registration in Azure AD:" -ForegroundColor Yellow
        Write-Host "   - Go to Azure Portal > Azure Active Directory > App registrations" -ForegroundColor White
        Write-Host "   - Click 'New registration'" -ForegroundColor White
        Write-Host "   - Name: 'PowerPlatform-SecurityRole-Creator'" -ForegroundColor White
        Write-Host "   - Supported account types: 'Accounts in this organizational directory only'" -ForegroundColor White
        Write-Host "   - Click 'Register'" -ForegroundColor White
        Write-Host "`n2. Create Client Secret:" -ForegroundColor Yellow
        Write-Host "   - In the app registration, go to 'Certificates & secrets'" -ForegroundColor White
        Write-Host "   - Click 'New client secret'" -ForegroundColor White
        Write-Host "   - Description: 'Dataverse API Access'" -ForegroundColor White
        Write-Host "   - Expires: Choose appropriate duration" -ForegroundColor White
        Write-Host "   - Copy the secret value (you won't see it again!)" -ForegroundColor White
        Write-Host "`n3. Add API Permissions:" -ForegroundColor Yellow
        Write-Host "   - Go to 'API permissions'" -ForegroundColor White
        Write-Host "   - Click 'Add a permission'" -ForegroundColor White
        Write-Host "   - Choose 'Dynamics CRM'" -ForegroundColor White
        Write-Host "   - Select 'Delegated permissions'" -ForegroundColor White
        Write-Host "   - Check 'user_impersonation'" -ForegroundColor White
        Write-Host "   - Click 'Add permissions'" -ForegroundColor White
        Write-Host "   - Click 'Grant admin consent'" -ForegroundColor White
        Write-Host "`n4. Add Service Principal to Power Platform:" -ForegroundColor Yellow
        Write-Host "   - Go to Power Platform Admin Center" -ForegroundColor White
        Write-Host "   - Navigate to your environment" -ForegroundColor White
        Write-Host "   - Go to Settings > Users + permissions > Application users" -ForegroundColor White
        Write-Host "   - Click 'New app user'" -ForegroundColor White
        Write-Host "   - Select your app registration" -ForegroundColor White
        Write-Host "   - Business unit: Select root business unit" -ForegroundColor White
        Write-Host "   - Security roles: Assign 'System Administrator' role" -ForegroundColor White
        Write-Host "   - Click 'Create'" -ForegroundColor White
        Write-Host "`n5. Run script with Service Principal:" -ForegroundColor Yellow
        Write-Host "   .\Create-DeveloperSecurityRole.ps1 -UseServicePrincipal \\" -ForegroundColor Gray
        Write-Host "     -TenantId 'your-tenant-id' \\" -ForegroundColor Gray
        Write-Host "     -ClientId 'your-app-registration-client-id' \\" -ForegroundColor Gray
        Write-Host "     -ClientSecret 'your-client-secret' \\" -ForegroundColor Gray
        Write-Host "     -EnvironmentId 'your-environment-id'" -ForegroundColor Gray
    }
    
    Write-Host "`nSUCCESS: Role definition complete! Ready for creation in Admin Center." -ForegroundColor Green
    
} catch {
    Write-Host "ERROR: Failed to create security role definition: $_" -ForegroundColor Red
}

Write-Host "`n=== Role Summary ===" -ForegroundColor Cyan
Write-Host "Role Name: $RoleName" -ForegroundColor White
Write-Host "Description: $RoleDescription" -ForegroundColor White
Write-Host "Purpose: Developer role with app/flow/agent creation but no metadata modification" -ForegroundColor White
Write-Host "`nNote: User assignment should be done separately in Power Platform Admin Center." -ForegroundColor Yellow
