# =============================================================================
# Resource Group
# =============================================================================

resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

# =============================================================================
# Networking - VNet, Subnet, NSG, Public IP, NIC
# =============================================================================

resource "azurerm_virtual_network" "main" {
  name                = "vnet-monitoring-playground"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags
}

resource "azurerm_subnet" "main" {
  name                 = "snet-default"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_network_security_group" "main" {
  name                = "nsg-monitoring-vm"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags

  security_rule {
    name                       = "Allow-RDP"
    priority                   = 1000
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "main" {
  subnet_id                 = azurerm_subnet.main.id
  network_security_group_id = azurerm_network_security_group.main.id
}

resource "azurerm_public_ip" "main" {
  name                = "pip-monitoring-vm"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

# Use azapi to create NIC with NSG in the same API call.
# The azurerm provider creates the NIC first then associates the NSG in a
# separate call, which trips the "Deny VM Creation Without NIC NSG" policy.
resource "azapi_resource" "nic" {
  type      = "Microsoft.Network/networkInterfaces@2024-01-01"
  name      = "nic-monitoring-vm"
  location  = azurerm_resource_group.main.location
  parent_id = azurerm_resource_group.main.id
  tags      = var.tags

  body = {
    properties = {
      networkSecurityGroup = {
        id = azurerm_network_security_group.main.id
      }
      ipConfigurations = [
        {
          name = "internal"
          properties = {
            subnet = {
              id = azurerm_subnet.main.id
            }
            privateIPAllocationMethod = "Dynamic"
            publicIPAddress = {
              id = azurerm_public_ip.main.id
            }
          }
        }
      ]
    }
  }
}

# =============================================================================
# Windows Virtual Machine
# =============================================================================

resource "azurerm_windows_virtual_machine" "main" {
  name                = "vm-monitoring"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  size                = var.vm_size
  admin_username      = var.admin_username
  admin_password      = var.admin_password
  tags                = var.tags

  network_interface_ids = [
    azapi_resource.nic.id,
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    name                 = "osdisk-monitoring-vm"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-datacenter-azure-edition"
    version   = "latest"
  }

  identity {
    type = "SystemAssigned"
  }
}
