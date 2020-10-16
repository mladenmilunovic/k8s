#specify number of instances as variable
variable "countvalue" {
    default = 5
}
variable "vmname" {
    default = "k8snode"
}

provider "azurerm" {
   features {}
}

# Create a resource group if it doesn’t exist
resource "azurerm_resource_group" "k8sgroup" {
    name     = "k8s_rg"
    location = "westeurope"

    tags = {
        environment = "k8s lab"
    }
}

# Create virtual network
resource "azurerm_virtual_network" "k8snetwork" {
    name                = "k8sVnet"
    address_space       = ["10.0.0.0/16"]
    location            = "westeurope"
    resource_group_name = "${azurerm_resource_group.k8sgroup.name}"

    tags = {
        environment = "k8s lab"
    }
}

# Create subnet
resource "azurerm_subnet" "k8ssubnet" {
    name                 = "k8ssubnet"
    resource_group_name  = "${azurerm_resource_group.k8sgroup.name}"
    virtual_network_name = "${azurerm_virtual_network.k8snetwork.name}"
    address_prefixes       = ["10.0.1.0/24"]
}

// # Create public IPs
// resource "azurerm_public_ip" "myterraformpublicip" {
//     count =  "${var.countvalue}"
//     name                         = "myPublicIP${count.index}"
//     location                     = "westeurope"
//     resource_group_name          = "${azurerm_resource_group.k8sgroup.name}"
//     allocation_method            = "Dynamic"

//     tags = {
//         environment = "k8s lab"
//     }
// }

# Create Network Security Group and rule
resource "azurerm_network_security_group" "myterraformnsg" {
    name                = "k8sNetworkSecurityGroup"
    location            = "westeurope"
    resource_group_name = "${azurerm_resource_group.k8sgroup.name}"
    
    // security_rule {
    //     name                       = "RDP"
    //     priority                   = 1001
    //     direction                  = "Inbound"
    //     access                     = "Allow"
    //     protocol                   = "Tcp"
    //     source_port_range          = "*"
    //     destination_port_range     = "3389"
    //     source_address_prefix      = "*"
    //     destination_address_prefix = "*"
    // }

    tags = {
        environment = "k8s lab"
    }
}

#Associate NSG to subnet
resource "azurerm_subnet_network_security_group_association" "mynsg" {
  subnet_id                 = "${azurerm_subnet.k8ssubnet.id}"
  network_security_group_id = "${azurerm_network_security_group.myterraformnsg.id}"
}

# Create network interface
resource "azurerm_network_interface" "myterraformnic" {
    count = "${var.countvalue}"
    name                      = format("NIC-${var.vmname}%02d", count.index + 1) 
    location                  = "westeurope"
    resource_group_name       = "${azurerm_resource_group.k8sgroup.name}"
    #dns_servers                   = ["10.0.1.10"]

    ip_configuration {
        name                          = format("NicConfiguration-${var.vmname}%02d", count.index + 1)
        subnet_id                     = "${azurerm_subnet.k8ssubnet.id}"
        private_ip_address_allocation = "Static"
        private_ip_address            = format("10.0.1.%02d", count.index + 11)
        // public_ip_address_id          = "${element(azurerm_public_ip.myterraformpublicip.*.id, count.index)}"
    }

    tags = {
        environment = "k8s lab"
    }
}

# Generate random text for a unique storage account name
resource "random_id" "randomId" {
    keepers = {
        // # Generate a new ID only when a new resource group is defined
        // resource_group = ${azurerm_resource_group.k8sgroup.name}
        resource_group_name         = "${azurerm_resource_group.k8sgroup.name}"
    }
    
    byte_length = 8
}

# Create storage account for boot diagnostics 
resource "azurerm_storage_account" "mystorageaccount" {
    name                        = "diag${random_id.randomId.hex}"
    resource_group_name         = "${azurerm_resource_group.k8sgroup.name}"
    location                    = "westeurope"
    account_tier                = "Standard"
    account_replication_type    = "LRS"

    tags = {
        environment = "k8s lab"
    }
}

# Create (and display) an SSH key
resource "tls_private_key" "example_ssh" {
  algorithm = "RSA"
  rsa_bits = 4096
}
output "tls_private_key" { value = tls_private_key.example_ssh.private_key_pem }


# Create virtual machine
resource "azurerm_linux_virtual_machine" "myterraformvm" {
    count = "${var.countvalue}"
    name                  = format("${var.vmname}%02d", count.index + 1)
    location              = "westeurope"
    resource_group_name   = "${azurerm_resource_group.k8sgroup.name}"
    network_interface_ids = ["${element(azurerm_network_interface.myterraformnic.*.id, count.index)}"]
    size                  = "Standard_D2ds_v4"
    computer_name  = format("${var.vmname}%02d", count.index + 1)
    admin_username = "mladen"
    disable_password_authentication = true

    admin_ssh_key {
        username       = "mladen"
        public_key     = tls_private_key.example_ssh.public_key_openssh
    }

    os_disk {
        name              = format("OsDisk-${var.vmname}%02d", count.index + 1)
        caching           = "ReadWrite"
        storage_account_type = "Premium_LRS"
    }

    source_image_reference {
        publisher = "OpenLogic"
        offer     = "CentOS"
        sku       = "7.5"
        version   = "latest"

        // publisher = "Canonical"
        // offer     = "UbuntuServer"
        // sku       = "18.10-LTS"
        // version   = "latest"
    }

    boot_diagnostics {
        storage_account_uri = "${azurerm_storage_account.mystorageaccount.primary_blob_endpoint}"
    }

    tags = {
        environment = "k8s lab"
    }
    }
