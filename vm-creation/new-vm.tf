# Configure the Azure provider
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0.2"
    }
  }

  required_version = ">= 1.1.0"
}

provider "azurerm" {
  features {}
}

# Always start with a resource group, if you don't have one
resource "azurerm_resource_group" "project1-rg" {
  name     = "project1-rg"
  location = "westus2"
}

# VM Setup ######################
#################################

# Create a virtual network and subnet
resource "azurerm_virtual_network" "project1-vnet" {
  resource_group_name = azurerm_resource_group.project1-rg.name
  location            = azurerm_resource_group.project1-rg.location
  name                = "project1-vnet"
  address_space       = ["10.0.0.0/16"]
}

# Create a subnet
resource "azurerm_subnet" "project1-subnet" {
  name                 = "project1-subnet"
  resource_group_name  = azurerm_resource_group.project1-rg.name
  virtual_network_name = azurerm_virtual_network.project1-vnet.name
  address_prefixes     = ["10.0.0.0/24"]
}

# Create a network interface for the VM
resource "azurerm_network_interface" "project1-nic" {
  name                = "project1-nic"
  location            = azurerm_resource_group.project1-rg.location
  resource_group_name = azurerm_resource_group.project1-rg.name
  # Select the subnet created earlier
  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.project1-subnet.id
    private_ip_address_allocation = "Dynamic"
  }
}

# Now the VM, using the NIC, subnet and resource group created earlier
resource "azurerm_linux_virtual_machine" "project1-vm" {
  name                            = "project1-vm"
  resource_group_name             = azurerm_resource_group.project1-rg.name
  location                        = azurerm_resource_group.project1-rg.location
  size                            = "Standard_D2s_v3"
  admin_username                  = "azureuser"
  admin_password                  = "Sz@jpc!Y2oHo*q"
  disable_password_authentication = false
  # Do not use in production - use SSH keys instead
  # Hardcoded password for demo purposes only
  provision_vm_agent = true
  # VM agent allows for extensions to be installed


  network_interface_ids = [
    azurerm_network_interface.project1-nic.id,
  ]


  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }
}

# Backup Setup ##################
#################################

# Set up vault for backups
resource "azurerm_recovery_services_vault" "project1-backup-vault" {
  name                = "project1-backup-vault"
  resource_group_name = azurerm_resource_group.project1-rg.name
  location            = azurerm_resource_group.project1-rg.location
  sku                 = "Standard"
}

# Create a backup policy for the VM
resource "azurerm_backup_policy_vm" "project1-backup-policy" {
  name                = "project1-backup-policy"
  resource_group_name = azurerm_resource_group.project1-rg.name
  recovery_vault_name = azurerm_recovery_services_vault.project1-backup-vault.name

  backup {
    frequency = "Daily"
    time      = "23:00"
  }
  retention_daily {
    count = 10
  }
}

# Backup the VM
resource "azurerm_backup_protected_vm" "project1-vm-backup" {
  resource_group_name = azurerm_resource_group.project1-rg.name
  recovery_vault_name = azurerm_recovery_services_vault.project1-backup-vault.name
  source_vm_id        = azurerm_linux_virtual_machine.project1-vm.id
  backup_policy_id    = azurerm_backup_policy_vm.project1-backup-policy.id
}

# Monitoring Setup ##############
#################################

# Create a Log Analytics workspace
resource "azurerm_log_analytics_workspace" "project1-law" {
  name                = "project1-law"
  location            = azurerm_resource_group.project1-rg.location
  resource_group_name = azurerm_resource_group.project1-rg.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

# Create an action group for alerts
resource "azurerm_monitor_action_group" "project1-action-group" {
  name                = "project1-action-group"
  resource_group_name = azurerm_resource_group.project1-rg.name
  short_name          = "proj1ag"
  email_receiver {
    name          = "admin-email"
    email_address = "ada@voden.ca"
  }
}

# Create metric alerts
resource "azurerm_monitor_metric_alert" "project1-cpu-alert" {
  name                = "project1-cpu-alert"
  resource_group_name = azurerm_resource_group.project1-rg.name
  scopes              = [azurerm_linux_virtual_machine.project1-vm.id]
  description         = "Alert for high CPU usage"
  severity            = 3

  criteria {
    metric_namespace = "Microsoft.Compute/virtualMachines"
    metric_name      = "Percentage CPU"
    aggregation     = "Average"
    operator        = "GreaterThan"
    threshold       = 80

  }

  action {
    action_group_id = azurerm_monitor_action_group.project1-action-group.id
  }
}