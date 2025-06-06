using namespace System.Net

Function Invoke-ListTeamsVoice {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Teams.Voice.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter
    $TenantId = (Get-Tenants | Where-Object -Property defaultDomainName -EQ $TenantFilter).customerId
    try {
        $Users = (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users?`$top=999&`$select=id,userPrincipalName,displayName" -tenantid $TenantId)
        $Skip = 0
        $GraphRequest = do {
            Write-Host "Getting page $Skip"
            $data = (New-TeamsAPIGetRequest -uri "https://api.interfaces.records.teams.microsoft.com/Skype.TelephoneNumberMgmt/Tenants/$($TenantId)/telephone-numbers?skip=$($Skip)&locale=en-US&top=999" -tenantid $TenantId).TelephoneNumbers | ForEach-Object {
                Write-Host 'Reached the loop'

                # Create the base object
                $CompleteRequest = $_ | Select-Object *

                # Handle AssignedTo property
                if ($_.TargetType -EQ "User" -and $_.TargetId) {
                    $CurrentTarget = $_.TargetId
                    $MatchedUser = $Users | Where-Object { $_.id -EQ $CurrentTarget }
                    $CompleteRequest | Add-Member -NotePropertyName 'AssignedTo' -NotePropertyValue $MatchedUser.userPrincipalName -Force
                } elseif ($_.TargetType -EQ "ResourceAccount" -and $_.TargetId) {
                    $CurrentTarget = $_.TargetId
                    $MatchedResource = $Users | Where-Object { $_.id -EQ $CurrentTarget }
                    $CompleteRequest | Add-Member -NotePropertyName 'AssignedTo' -NotePropertyValue $MatchedResource.displayName -Force
                }
                if ($CompleteRequest.AssignedTo -EQ $null) {
                    $CompleteRequest | Add-Member -NotePropertyName 'AssignedTo' -NotePropertyValue 'Unassigned' -Force
                }

                # Handle AcquisitionDate property
                if ($CompleteRequest.AcquisitionDate) {
                    $CompleteRequest.AcquisitionDate = $_.AcquisitionDate -split 'T' | Select-Object -First 1
                } else {
                    $CompleteRequest | Add-Member -NotePropertyName 'AcquisitionDate' -NotePropertyValue 'Unknown' -Force
                }

                $CompleteRequest
            }
            Write-Host 'Finished the loop'
            $Skip = $Skip + 999
            $Data
        } while ($data.Count -eq 999)
        Write-Host 'Exiting the Do.'
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = [HttpStatusCode]::Forbidden
        $GraphRequest = $ErrorMessage
    }
    Write-Host "Graph request is: $($GraphRequest)"
    Write-Host 'Returning the response'
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($GraphRequest)
        })

}
