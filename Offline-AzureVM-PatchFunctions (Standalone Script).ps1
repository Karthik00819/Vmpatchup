<#
	.SYNOPSIS
		Azure VM Patching Helper:  Starts specified list of Azure Virtual Machines for the specified durection then shuts them back down.
	
	.DESCRIPTION
		Azure VM Patching Helper:  Master function to coordinate patching procedure for Azure Virtual Machines kept primarily in an "OFFLINE" power state.  This utility will power the specified virtual machines up, keep them online for a user-specified interval, and then shut them back down when finished.  This routine can be scheduled around your organization's patching policy to ensure that even offline Azure Virtaul Machines are regulatly patched.
		
		Starts specified list of Azure Virtual Machines for the specified durection then shuts them back down.  This function controls the entire process from start to finish, and runs all validation checks, handles all errors, and operates the countdown timers used in the script logic.
		

        FUNCTIONS LIST
        --------------

        ### VALIDATION FUNCTIONS ###
        
            Check-AzureVMRunning              : Boolean check if single Azure VM is running
            Check-AzureVMOffline              : Boolean check if single Azure VM is offline
            Validate-TargetAzureVMFound       : Validates target Azure VMs are found in current subscription context
            Validate-AllTargetAzureVMsFound   :  Bulk Validation/Error Handling to ensure that all for ALL Azure VMs targetted by this script are found in the current subscription context
            Validate-AllTargetAzureVMsOffline : Bulk Validation/Error Handling to ensure ALL Azure VMs targetted by this script were stopped successfully
            Validate-AllTargetAzureVMsRunning :  Bulk Validation/Error Handling to ensure ALL Azure VMs targetted by this script were started successfully

        ### LIST FUNCTIONS ###
        
            Check-AzureVMPowerState           : Lists power state of single target Azure VM
            List-TargetAzureVMsStatus         : Lists power state of ALL target Azure VMs

        ### POWER CONTROL FUNCTIONS ###
        
            Start-TargetAzureVMs              : Bulk operation to start ALL target Azure VMs
            Stop-TargetAzureVMs               : Bulk operation to stop ALL target Azure VMs

        ### SUBSCRIPTION BULK OPERATIONS ###

            Get-AllSubscriptionOfflineAzureVMs   : Stand-alone subscription-level script to get ALL offline Azure VMs in the current subscription
            Start-AllSubscriptionOfflineAzureVMs: Stand-alone subscription-level script to start ALL offline Azure VMs in the current subscription
            
        ### MASTER INIT FUNCTION ###
            Start-AzureVMPatchingProcedure     : Master function to provide patching automation for Azure VMs that are kept offline.  Powers them on for specified duration then powers them back off, allowing patches to be regularly applied to offline machines.


		IMPLEMENATATION
		---------------
		* Designed to integrate as Azure DevOps pipeline task
		* Esure that maintenanance phase is assigned to the resource via tags and the Service Now CMDB Configuration Item for the resource
		* Implement as an Azure DevOps BUILD or RELEASE pipeline task on a set schedule matching the patching policy
		* A good default MAINTENANCE PHASE is Phase 6 A/B/C/D (choose one, stagger for clusters)
		* Maintenance Phase 6 kicks off the last Sunday of every month
		* IMPORTANT:  It is assumed that you will set the subscription context via Azure DevOps.
		This script can only target VMs inside of the current context.  You will need to deploy a seperate instance for each seperate
		Azure Subscription you want to target
		* When calling the script from Azure DevOps you must provide a list of machine names as an input parameter/argument
		
		
		LOGIC OVERVIEW
		--------------
		* Script validates that all VMs are found within the current subscription context (error on fail)
		* Starts all VMs that are currently stopped (error on fail)
		* Wait timer counts down to allow machines time to start
		* Validates that all targeted machines are "RUNNING" as expected (error on fail)
		* Machine remains online for specified number of hours so that it can be patched
		* After specified interval elapses the script shuts down all VMs (error on fail)
		* Wait timer allow VMs time to shut down
		* Validates that all machines are in a SHUTDOWN STATE (error on fail)
		
		NOTES
		-----
		This script operates out of the current subscription context.  It is assumed that this context will be set prior to running the script.
	
	.PARAMETER Target_VM_List
		A comma-seperated string list of Virtual Machine hostnames to target (format: 'Machine1','Machine2','Machine3') [Note: encapsulate each hostname individually within single or double quotation marks, see above)
	
	.PARAMETER Wait_Timer_Hours
		The number of hours that the machines will remain online before being automatically shut down.
	
	.PARAMETER Validation_Timer_Minutes
		The number of minutes to wait after issuing a STARTUP or SHUTODOWN command prior to running a validation procedure to ensure that all VMs are in the expected running state.
	
	.EXAMPLE
		Call this script and provide a list of hostnames to target:
		
		EX:  path/to/thisscript.ps1 -Target_CM_List "VM1","VM2","VM3","VM4"
	
	.NOTES
		IMPORTANT!  This script operates out of the current subscription context.  It is assumed that this context will be set prior to running the script.
#>

### SCRIPT IPUT PARAMETERS ###


param
    (
	    [Parameter(Mandatory = $true,
	               HelpMessage = 'A comma-seperated string list of Virtual Machine hostnames to target ')]
	    [ValidateNotNull()]
	    [ValidateNotNullOrEmpty()]
	    [string[]]
	    $Target_VM_List,
	    [Parameter(HelpMessage = 'The number of hours that the machines will remain online before being automatically shut down.')]
	    [ValidateNotNullOrEmpty()]
	    [int]
	    $Wait_Timer_Hours = 24,
	    [Parameter(HelpMessage = 'Minutes to wait for machines to shutdown/start up')]
	    [ValidateNotNullOrEmpty()]
	    [int]
	    $Validation_Timer_Minutes = 5
    )



function Start-TargetAzureVMs
        {
<#
	.SYNOPSIS
		Starts all target Virtual Machines
	
	.DESCRIPTION
		Starts all target Virtual Machines
	
	.PARAMETER Target_VM_List
		A description of the Target_VM_List parameter.
	
	.EXAMPLE
				PS C:\> Start-TargetAzureVMs
	
#>
	        param
	            (
		        [string[]]
		        $Target_VM_List = $Target_VM_List
	            )
	

            ## Results Arrays ##
            $Failed_List = @()
            $Success_List = @()
            $NotFound_List = @()
            $Found_List = @()

            $Target_VM_Count = $Target_VM_List.Count

  
            $ALLVMS = Get-AzureRMVM -Status

            ### VALIDATE ###
            Foreach ($VM in $Target_VM_List)
                {
                Write-Host "Validating existence of $VM"
                $TargetVM =  $ALLVMS | Where {$_.name -like $VM}
                if (!($TargetVM)){
                    Write-Warning "WARNING: Failed to locate Target VM $VM - check your subscription context and ensure the resource exists"
                    $NotFound_List += $VM
                    }
                else{
                    $Found_List += $TargetVM
                    #$TargetVM | Select Name,ResourceGroupName,Location,PowerState
                    }
                }

    
            ### WAKEY WAKEY ###
            Foreach ($VM in $Found_List)
                {
                Write-Host "Checking status of $VM"
                if (Check-AzureVMOffline)
                    {
                    try {
                        $VM | Start-AzureRmVM -ErrorAction Stop
                        $Success_List += $VM
                        }
                    catch{
                        $Failed_List += $VM
                        }
                    }
                }

             ### ERROR HANDLING AND RESULTS ###
             if ($Failed_List.Count -ge 1)
                {
                throw "Failed to start $($Failed_List.Count) VMs: $($Failed_List.name -join ',')"
                }   
             elseif ($NotFound_List.Count -gt 1)
                {
                throw "Failed to locate $($NotFound_List.Count) VMs: $($NotFound_List.name -join ',')"
                }
            else {Write-Host "Successfully started $($Success_List.Count) VMs!" -ForegroundColor Green}
        }


function Stop-TargetAzureVMs
    {
<#
	.SYNOPSIS
		Shuts down all target VMs
	
	.DESCRIPTION
		Shuts down all target VMs
	
	.PARAMETER Target_VM_List
		A description of the Target_VM_List parameter.
	
	.EXAMPLE
				PS C:\> Stop-TargetAzureVMs
	
#>
	
	    param
	        (
		    [string[]]
		    $Target_VM_List = $Target_VM_List
	        )
	
        ## RESULT ARRAYS ##
        $Failed_List = @()
        $Success_List = @()
        $NotFound_List = @()
        $Found_List = @()

        $Target_VM_Count = $Target_VM_List.Count

        $ALLVMS = Get-AzureRMVM -Status
        

        Foreach ($VM in $Target_VM_List)
            {
            Write-Host "Validating existence of $VM"
            $TargetVM =  $ALLVMS | Where {$_.name -like $VM}
            if (!($TargetVM)){
                Write-Warning "WARNING: Failed to locate Target VM $VM - check your subscription context and ensure the resource exists"
                $NotFound_List += $VM
                }
            else{
                $Found_List += $TargetVM
                #$TargetVM | Select Name,ResourceGroupName,Location,PowerState
                }
            }

        Foreach ($VM in $Found_List)
            {
            Write-Host "Checking status of $VM"
            if (Check-AzureVMOffline)
                {
                try {
                    $VM | Stop-AzureRmVM -Force -ErrorAction Stop
                    $Success_List += $VM
                    }
                catch{
                    $Failed_List += $VM
                    }
                }
            }

        ### ERROR HANDLING AND RESULTS ###
         if ($Failed_List.Count -ge 1)
            {
            throw "Failed to stop $($Failed_List.Count) VMs: $($Failed_List.name -join ',')"
            }   
         elseif ($NotFound_List.Count -gt 1)
            {
            throw "Failed to locate $($NotFound_List.Count) VMs: $($NotFound_List.name -join ',')"
            }
        else {Write-Host "Successfully started $($Success_List.Count) VMs!" -ForegroundColor Green}
    }


function Check-AzureVMPowerState
{
<#
	.SYNOPSIS
		Checks Power State (RUNNING / SHUTDOWN) for target VMs
	
	.DESCRIPTION
		Checks Power State (RUNNING / SHUTDOWN) for target VMs
	
	.PARAMETER Target_VM_List
		A description of the Target_VM_List parameter.
	
	.EXAMPLE
				PS C:\> Check-AzureVMPowerState
	
#>
	
    param
	    (
		    [string[]]
		    $Target_VM_List = $Target_VM_List
	    )
	
    ## Results Arrays ##
        $Failed_List = @()
        $Success_List = @()
        $NotFound_List = @()
        $Found_List = @()
        $Running_VMs =  @()
        $Stopped_VMs = @()

        $Target_VM_Count = $Target_VM_List.Count

        ## Lookup ##
        $ALLVMS = Get-AzureRMVM -Status
        Foreach ($VM in $Target_VM_List)
            {
            Write-Host "Checking status of $VM" -ForegroundColor Cyan
            $TargetVM =  $ALLVMS | Where {$_.name -like $VM}
            if (!($TargetVM)){
                Write-Warning "WARNING: Failed to locate Target VM $VM - check your subscription context and ensure the resource exists"
                $NotFound_List += $VM
                }
            else{
                $Found_List += $TargetVM
                #$TargetVM | Select Name,ResourceGroupName,Location,PowerState
                }
            }
  
        return $Found_List
    }


function Validate-TargetAzureVMFound
    {
<#
	.SYNOPSIS
		Stand-alone command that checks if a single Azure VM is found in the current subscription context
	
	.DESCRIPTION
		Stand-alone command that checks if a single Azure VM is found in the current subscription context
	
	.PARAMETER VMName
		A description of the VMName parameter.
	
	.EXAMPLE
				PS C:\> Validate-TargetAzureVMFound
#>
	
	    param
	        (
		    $VMName
	        )
	
        Write-Host "Confirming VM$($VMName) found" -ForegroundColor Cyan
    
        [bool]($ALLVMS | Where {$_.name -like $VMName}) -and ([bool]($ALLVMS | Where {$_.name -like $VMName}).Count -eq 1)
    }


function Validate-AllTargetAzureVMsFound
    {
<#
	.SYNOPSIS
		Enumerates all VMs and validates that all target host names are found within the current subscription context
	
	.DESCRIPTION
		Enumerates all VMs and validates that all target host names are found within the current subscription context
	
	.PARAMETER Target_VM_List
		A description of the Target_VM_List parameter.
	
	.EXAMPLE
				PS C:\> Validate-AllTargetAzureVMsFound
	
	.NOTES
		Set the subscription context prior to calling this script
#>
	
	    param
	        (
		    [string[]]
		    $Target_VM_List = $Target_VM_List
	        )
	
        Write-Host "Validating list of target VMs" -ForegroundColor Cyan

        ### OUTPUT ARRAYS ###
        $ALLVMS = Get-AzureRMVM -Status
        $Fail = $False
        $FailList = @()

        ### ITERATE THROUGH TARGET VMS ###
        Foreach ($VM in $Target_VM_List)
            {
            Write-Host "Checking status of $VM" -ForegroundColor Cyan
            $TargetVM =  $ALLVMS | Where {$_.name -like $VM}
            if ((!($TargetVM)) -or ($TargetVM.Count -ne 1)){
                Write-Warning "WARNING: Failed to locate Target VM $VM - check your subscription context and ensure the resource exists"
                $Fail = $True
                $FailList += $VM
                }
            else{
                Write-Host "Successfully located Target VM $VM " -ForegroundColor Green
                #$TargetVM | Select Name,ResourceGroupName,Location,PowerState
                }
            }

        ### OUTPUT HANDLING ###
        if ($Fail){
            Write-Warning "Failed to locate one or more target VMs"
            Write-Host $FailList -ForegroundColor Yellow
            return $False
            }
        else {return $True}
    }



function Check-AzureVMRunning
    {
<#
	.SYNOPSIS
		Stand-alone function to check a single Azure VM to verify it is running
	
	.DESCRIPTION
		Stand-alone function to check a single Azure VM to verify it is running
	
	.PARAMETER VMObject
		A description of the VMObject parameter.
	
	.EXAMPLE
				PS C:\> Check-AzureVMRunning
	
	
#>
	
	[OutputType([bool])]
	param
	    (
		$VMObject
	    )
	
    if ($VMObject.PowerState -like 'VM Running')
            {return $True}
        else{return $False}
    }



function Check-AzureVMOffline
    {
    <#
	    .SYNOPSIS
		    Stand-alone function to check a single Azure VM to verify it is shut down
	
	    .DESCRIPTION
		    Stand-alone function to check a single Azure VM to verify it is shut down
	
	    .PARAMETER VMObject
		    A description of the VMObject parameter.
	
	    .EXAMPLE
				    PS C:\> Check-AzureVMOffline
	
	    .NOTES
		    Use as additional fail-safe and as part of error logic

    #>
	
	    param
	        (
		    $VMObject
	        )
	
    if ($VMObject.PowerState -like 'VM Running')
            {return $false}
        else{return $true}
    }



function Validate-AllTargetAzureVMsOffline
    {
    <#
	    .SYNOPSIS
		    Bulk function that validates all target servers have been successfully shut down
	
	    .DESCRIPTION
		    Bulk function that validates all target servers have been successfully shut down
	
	    .PARAMETER Target_VM_List
		    A description of the Target_VM_List parameter.
	
	    .EXAMPLE
		    PS C:\> Validate-AllTargetAzureVMsOffline
    #>
	
	    [OutputType([bool])]
	    param
	        (
		    [string[]]
		    $Target_VM_List = $Target_VM_List
	        )
	
	    $AllVMs = Get-AzureRMVM -Status
        $FoundAwakeVMs = $False
    
        Foreach ($TargetVM in $Target_VM_List)
            {
            $Match = ($ALLVMS | Where {$_.name -like $TargetVM})
            if ($Match.PowerState -like 'VM Running'){$FoundAwakeVMs = $True}
            }

        if ($FoundAwakeVMs)
            {
            Write-Warning "One or more VMs were unable to be shut down"
            #List-TargetAzureVMsStatus
            return $False
            }
        else{
            Write-Host "Successfully validated all VMs are shut down!" -ForegroundColor Green
            return $True
            }
    }


function Validate-AllTargetAzureVMsRunning
    {
<#
	.SYNOPSIS
		Bulk validation to ensure that all target VMs are currently running as expected
	
	.DESCRIPTION
		Bulk validation to ensure that all target VMs are currently running as expected
	
	.PARAMETER Target_VM_List
		A description of the Target_VM_List parameter.
	
	.EXAMPLE
				PS C:\> Validate-AllTargetAzureVMsRunning
	
	.NOTES
		Use as additional fail-safe and as part of error logic
#>
	
	    [OutputType([bool])]
	    param
	    (
		    [string[]]
		    $Target_VM_List = $Target_VM_List
	    )
	
	    $AllVMs = Get-AzureRMVM -Status
        $FoundSleepingVMs = $False
    
        Foreach ($TargetVM in $Target_VM_List)
            {
            $Match = ($ALLVMS | Where {$_.name -like $TargetVM})
            if ($Match.PowerState -notlike 'VM Running'){$FoundSleepingVMs = $True}
            }

  
        if ($FoundSleepingVMs)
            {
            Write-Warning "One or more VMs were unable to be started"
            #List-TargetAzureVMsStatus
            return $False
            }
        else{
            Write-Host "Successfully validated all VMs are started!" -ForegroundColor Green
            return $True
            }
    }


function List-TargetAzureVMsStatus
    {
<#
	.SYNOPSIS
		Creates a simple list displaying the power state of all target VMs
	
	.DESCRIPTION
		Creates a simple list displaying the power state of all target VMs
	
	.PARAMETER Target_VM_List
		A description of the Target_VM_List parameter.
	
	.EXAMPLE
				PS C:\> List-TargetAzureVMsStatus
	
	.NOTES
		Use for diagnostic or console display purposes
#>
	
	    param
	    (
		    [string[]]
		    $Target_VM_List = $Target_VM_List
	    )
	
	    $AllVMs = Get-AzureRMVM -Status
        $VMReport = @()
        Foreach ($VM in $Target_VM_List)
            {
            $VMReport += $AllVMs | Where {$_.name -like $VM}
            }

        $VMReport | Select Name,ResourceGroupName,PowerState,Location,Id
    }


function Get-AllSubscriptionOfflineAzureVMs
    {
<#
	.SYNOPSIS
		Stand-alone function to return ALL virtual machines currently OFFLINE in the current Azure subscription
	
	.DESCRIPTION
		Stand-alone function to return ALL virtual machines currently OFFLINE in the current Azure subscription
	
	.EXAMPLE
		PS C:\> Get-AllSubscriptionOfflineAzureVMs
	
	.NOTES
		WARNING:  This function does not utilize the user-specified list of target VMs - it targets ALL VMs that are offline in the current Azure subscription!
#>
	
    ### FIND SLEEPING VMs ###
        $Sleeping_VMs = Get-AzureRmVM -Status | Where {$_.PowerState -notlike 'VM running'} 

        ### REPORT  SLEEPING VMs ###
        if ($Sleeping_VMs)
            {
            Write-Host "Found a total of $($Sleeping_VMs.Count) sleeping VMs" -ForegroundColor Cyan
            }
        else{
            Write-Host "Found a total of 0 sleeping VMs." -ForegroundColor Green
            }

        ### RETURN SLEEPING VMs ###
        return $Sleeping_VMs
    }



function Start-AllSubscriptionOfflineAzureVMs
    {
<#
	.SYNOPSIS
		Stand-alone function that starts ALL offline Azure Virtual Machines in the current subscription context
	
	.DESCRIPTION
		SYNOPSIS
				Stand-alone function to return ALL virtual machines currently OFFLINE in the current Azure subscription
			
			.DESCRIPTION
				Stand-alone function to return ALL virtual machines currently OFFLINE in the current Azure subscription
			
			.EXAMPLE
						PS C:\> Find-AllOfflineAzureVMs
			
			.NOTES
		Stand-alone function that starts ALL offline Azure Virtual Machines in the current subscription context
	
	.EXAMPLE
				PS C:\> Start-AllSubscriptionOfflineAzureVMs
	
	.NOTES
			WARNING:  This function does not utilize the user-specified list of target VMs - it targets ALL VMs that are offline in the current Azure subscription!
#>
	
    ### VARS AND ARRAYS ###
        $Target_VMs = Get-AllSubscriptionOfflineAzureVMs
        $Failed_ToStart_VMs = @()
        $Successfully_Started_VMS = @()

        ### WAKEY WAKEY ###
        Foreach ($VM in $Target_VMs)
            {
            Write-Host "Attempting to wake up sleeping VM $($Sleeping_VMs.Name)"
        
            try { 
                $VM | Start-AzureRMVM
                $Successfully_Started_VMS += $VM    
                }
            catch{ $Failed_ToStart_VMs += $VM }
            }

        ### USER OUTPUT DISPLAY ###
        if ($Failed_ToStart_VMs)
            {
            throw "One or more VMs failed to start - the following VMs could not be started: $($Failed_ToStart_VMs.name -join ', ')"
            }
        elseif (!($Target_VMs)){Write-Host "Did not find any sleeping VMs" -ForegroundColor Yellow}
        else{Write-Host "Successfully started all VMs" -ForegroundColor Green}
    }


function Start-AzureVMPatchingProcedure
    {
<#
	.SYNOPSIS
		Azure VM Patching Helper:  Starts specified list of Azure Virtual Machines for the specified durection then shuts them back down.
	
	.DESCRIPTION
		Azure VM Patching Helper:  Master function to coordinate patching procedure for Azure Virtual Machines kept primarily in an "OFFLINE" power state.  This utility will power the specified virtual machines up, keep them online for a user-specified interval, and then shut them back down when finished.  This routine can be scheduled around your organization's patching policy to ensure that even offline Azure Virtaul Machines are regulatly patched.
		
		Starts specified list of Azure Virtual Machines for the specified durection then shuts them back down.  This function controls the entire process from start to finish, and runs all validation checks, handles all errors, and operates the countdown timers used in the script logic.  
	
	.EXAMPLE
				PS C:\> Start-AzureVMPatchingProcedure
	
	.NOTES
		Additional information about the function.
#>
	

        #VALIDATE#
          if (!(Validate-AllTargetAzureVMsFound))
            {throw "Failed to locate one or more VMs listed"}
    
        #Wake VMs#
        Start-TargetAzureVMs

        #Wait for Waking VMs#
        Write-Host "Waiting $($Validation_Timer_Minutes * 60) minutes for VMs to wake up...[$(Get-Date)]" -ForegroundColor Cyan
        Start-Sleep -Seconds ($Validation_Timer_Minutes * 60)
    
        #Validate All VMs Awake#
        if(!(Validate-AllTargetAzureVMsRunning)){throw "One or more VMs failed to start"}

        #Wait for Patching#
        Write-Host "VMs online - waiting for $($Wait_Timer_Hours) hours before shutting back down...[$(Get-Date)]"  -ForegroundColor Cyan
        Start-Sleep -Seconds (60 * 60 * $Wait_Timer_Hours)

        #Shut down after timer#
        Stop-TargetAzureVMs

        Write-Host "Waiting $($Validation_Timer_Minutes * 60) minutes for VMs to shut down...[$(Get-Date)]"  -ForegroundColor Cyan
        Start-Sleep -Seconds ($Validation_Timer_Minutes * 60)
    
        #Validate All Asleep#
        if (!(Validate-AllTargetAzureVMsOffline)){throw "Failed to shut down one or more VMs"}

        #Report Current State#
        List-TargetAzureVMsStatus | ft -AutoSize
    }


#### EXECUTION LOGIC ###

    Start-AzureVMPatchingProcedure 
