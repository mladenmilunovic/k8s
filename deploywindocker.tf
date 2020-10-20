#specify number of instances as variable
variable "countvalue" {
    default = 3
}
variable "vmname" {
    default = "windocker"
}

provider "azurerm" {
   features {}
}

# Create a resource group if it doesn’t exist
resource "azurerm_resource_group" "myterraformgroup" {
    name     = "windocker_rg"
    location = "westeurope"

    tags = {
        environment = "windocker lab"
    }
}

# Create virtual network
resource "azurerm_virtual_network" "myterraformnetwork" {
    name                = "windockerVnet"
    address_space       = ["10.0.0.0/16"]
    location            = "westeurope"
    resource_group_name = "${azurerm_resource_group.myterraformgroup.name}"

    tags = {
        environment = "windocker lab"
    }
}

# Create subnet
resource "azurerm_subnet" "myterraformsubnet" {
    name                 = "windockerSubnet"
    resource_group_name  = "${azurerm_resource_group.myterraformgroup.name}"
    virtual_network_name = "${azurerm_virtual_network.myterraformnetwork.name}"
    address_prefixes       = ["10.0.1.0/24"]
}

# Create public IPs
resource "azurerm_public_ip" "myterraformpublicip" {
    count =  "${var.countvalue}"
    name                         = "myPublicIP${count.index}"
    location                     = "westeurope"
    resource_group_name          = "${azurerm_resource_group.myterraformgroup.name}"
    allocation_method            = "Dynamic"

    tags = {
        environment = "windocker lab"
    }
}

# Create Network Security Group and rule
resource "azurerm_network_security_group" "myterraformnsg" {
    name                = "windockerNetworkSecurityGroup"
    location            = "westeurope"
    resource_group_name = "${azurerm_resource_group.myterraformgroup.name}"
    
    security_rule {
        name                       = "RDP"
        priority                   = 1001
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "178.148.188.246/32"
        source_address_prefix      = "*"
        destination_address_prefix = "*"
    }

    security_rule {
        name                       = "Web"
        priority                   = 1002
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "80"
        source_address_prefix      = "*"
        destination_address_prefix = "*"
    }

    tags = {
        environment = "windocker lab"
    }
}

#Associate NSG to subnet
resource "azurerm_subnet_network_security_group_association" "mynsg" {
  subnet_id                 = "${azurerm_subnet.myterraformsubnet.id}"
  network_security_group_id = "${azurerm_network_security_group.myterraformnsg.id}"
}

# Create network interface
resource "azurerm_network_interface" "myterraformnic" {
    count = "${var.countvalue}"
    name                      = format("NIC-${var.vmname}%02d", count.index + 1) 
    location                  = "westeurope"
    resource_group_name       = "${azurerm_resource_group.myterraformgroup.name}"
    #dns_servers                   = ["10.0.1.10"]

    ip_configuration {
        name                          = format("NicConfiguration-${var.vmname}%02d", count.index + 1)
        subnet_id                     = "${azurerm_subnet.myterraformsubnet.id}"
        private_ip_address_allocation = "Static"
        private_ip_address            = format("10.0.1.%02d", count.index + 11)
        public_ip_address_id          = "${element(azurerm_public_ip.myterraformpublicip.*.id, count.index)}"
    }

    tags = {
        environment = "windocker lab"
    }
}

# Generate random text for a unique storage account name
resource "random_id" "randomId" {
    keepers = {
        // # Generate a new ID only when a new resource group is defined
        // resource_group = ${azurerm_resource_group.myterraformgroup.name}
        resource_group_name         = "${azurerm_resource_group.myterraformgroup.name}"
    }
    
    byte_length = 8
}

# Create storage account for boot diagnostics 
resource "azurerm_storage_account" "mystorageaccount" {
    name                        = "diag${random_id.randomId.hex}"
    resource_group_name         = "${azurerm_resource_group.myterraformgroup.name}"
    location                    = "westeurope"
    account_tier                = "Standard"
    account_replication_type    = "LRS"

    tags = {
        environment = "windocker lab"
    }
}

# Create virtual machine
resource "azurerm_virtual_machine" "myterraformvm" {
    count = "${var.countvalue}"
    name                  = format("${var.vmname}%02d", count.index + 1)
    location              = "westeurope"
    resource_group_name   = "${azurerm_resource_group.myterraformgroup.name}"
    network_interface_ids = ["${element(azurerm_network_interface.myterraformnic.*.id, count.index)}"]
    vm_size               = "Standard_D2ds_v4"
    // for exchange Standard_D4ds_v4
    
    storage_os_disk {
        name              = format("OsDisk-${var.vmname}%02d", count.index + 1)
        caching           = "ReadWrite"
        create_option     = "FromImage"
        managed_disk_type = "Premium_LRS"
    }

    storage_image_reference {
        publisher = "MicrosoftWindowsServer"
        offer     = "WindowsServer"
        sku       = "2019-datacenter-with-Containers"
        // Check file AzureSKU for more details
        version   = "latest"
    }

    os_profile {
        computer_name  = format("${var.vmname}%02d", count.index + 1)
        admin_username = "mladen"
        admin_password = "P@ssw0rd1234"
    }

    os_profile_windows_config {
        enable_automatic_upgrades = false
        provision_vm_agent = true
    }

    boot_diagnostics {
        enabled = "true"
        storage_uri = "${azurerm_storage_account.mystorageaccount.primary_blob_endpoint}"
    }

    tags = {
        environment = "windocker lab"
    }
    }
