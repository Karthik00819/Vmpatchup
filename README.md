# Start-AzureOfflineVMPatching
PowerShell CICD script to facilitate patching of Azure Virtual Machines that are primarily kept offline.  Starts servers for specified interval and shuts them down after patching maintenance window.

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
