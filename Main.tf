provider "azurerm" {
  version = "=1.12.0"
}
resource "azurerm_resource_group" "k8s" {
    name     = "${var.resource_group_name}"
    location = "${var.location}"
}
resource azurerm_network_security_group "aks_advanced_network" {
  name                = "akc-k8s-nsg"
  location            = "${azurerm_resource_group.k8s.location}"
  resource_group_name = "${azurerm_resource_group.k8s.name}"

  security_rule {
    name                       = "AllowInternetOutbound"
    priority                   = 400
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "0.0.0.0/0"
  }
  security_rule {
    name                       = "Allow-Outside-From-IP"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

}
 resource "azurerm_virtual_network" "aks_advanced_network" {
  name                = "akc-k8s-vnet"
  location            = "${azurerm_resource_group.k8s.location}"
  resource_group_name = "${azurerm_resource_group.k8s.name}"
  address_space       = ["${join("", list(var.IPAddressPrefix, ".0.0/16"))}"]
}
 resource "azurerm_subnet" "aks_subnet" {
  name                      = "akc-k8s-subnet"
  resource_group_name       = "${azurerm_resource_group.k8s.name}"
  network_security_group_id = "${azurerm_network_security_group.aks_advanced_network.id}"
  address_prefix            = "${join("", list(var.IPAddressPrefix, ".10.0/24"))}"
  virtual_network_name      = "${azurerm_virtual_network.aks_advanced_network.name}"
  route_table_id            = "${azurerm_route_table.k8s-subnet.id}"
  depends_on = ["azurerm_route_table.k8s-subnet"
                ]
}
resource "azurerm_subnet" "mgmt_subnet" {
  name                      = "mgmt-subnet"
  resource_group_name       = "${azurerm_resource_group.k8s.name}"
  network_security_group_id = "${azurerm_network_security_group.aks_advanced_network.id}"
  address_prefix            = "${join("", list(var.IPAddressPrefix, ".0.0/24"))}"
  virtual_network_name      = "${azurerm_virtual_network.aks_advanced_network.name}"
}
resource "azurerm_subnet" "untrust_subnet" {
  name                      = "untrust-subnet"
  resource_group_name       = "${azurerm_resource_group.k8s.name}"
  network_security_group_id = "${azurerm_network_security_group.aks_advanced_network.id}"
  address_prefix            = "${join("", list(var.IPAddressPrefix, ".1.0/24"))}"
  virtual_network_name      = "${azurerm_virtual_network.aks_advanced_network.name}"
}
resource "azurerm_subnet" "trust_subnet" {
  name                      = "trust-subnet"
  resource_group_name       = "${azurerm_resource_group.k8s.name}"
  network_security_group_id = "${azurerm_network_security_group.aks_advanced_network.id}"
  address_prefix            = "${join("", list(var.IPAddressPrefix, ".2.0/24"))}"
  virtual_network_name      = "${azurerm_virtual_network.aks_advanced_network.name}"
}
resource "azurerm_subnet" "appgateway_subnet" {
  name                      = "appgateway-subnet"
  resource_group_name       = "${azurerm_resource_group.k8s.name}"
  network_security_group_id = "${azurerm_network_security_group.aks_advanced_network.id}"
  address_prefix            = "${join("", list(var.IPAddressPrefix, ".50.0/24"))}"
  virtual_network_name      = "${azurerm_virtual_network.aks_advanced_network.name}"
  route_table_id            = "${azurerm_route_table.appgateway-subnet.id}"
  depends_on = ["azurerm_route_table.appgateway-subnet"
                ]
}
//Routes for App Gateway subnet

resource "azurerm_route_table" "appgateway-subnet" {
  name                = "appgateway-subnet"
  location            = "${azurerm_resource_group.k8s.location}"
  resource_group_name = "${azurerm_resource_group.k8s.name}"

  disable_bgp_route_propagation = false

  route {
    name           = "k8s-subnet"
    address_prefix = "${join("", list(var.IPAddressPrefix, ".10.0/24"))}"
    next_hop_type  = "VirtualAppliance"
    next_hop_in_ip_address = "${join("", list(var.IPAddressPrefix, ".1.4"))}"
  }
  depends_on = [
                ]
}

//Routes for k8s subnet

resource "azurerm_route_table" "k8s-subnet" {
  name                = "k8s-subnet"
  location            = "${azurerm_resource_group.k8s.location}"
  resource_group_name = "${azurerm_resource_group.k8s.name}"

  disable_bgp_route_propagation = false

  route {
    name           = "appgateway-subnet"
    address_prefix = "${join("", list(var.IPAddressPrefix, ".50.0/24"))}"
    next_hop_type  = "VirtualAppliance"
    next_hop_in_ip_address = "${join("", list(var.IPAddressPrefix, ".2.4"))}"
  }
/*  route {
    name           = "default"
    address_prefix = "0.0.0.0/0"
    next_hop_type  = "VirtualAppliance"
    next_hop_in_ip_address = "${join("", list(var.IPAddressPrefix, ".2.4"))}"
  }*/
  depends_on = [
                ]
}

//Application Gateway Config
# Create Dynamic Public IP Addresses
resource "azurerm_public_ip" "pip_appgateway" {
  name                         = "pip-appgateway"
  location                     = "${azurerm_resource_group.k8s.location}"
  resource_group_name          = "${azurerm_resource_group.k8s.name}"
  public_ip_address_allocation = "dynamic"
}

# Create Application Gateways
resource "azurerm_application_gateway" "application-gateway" {
  name                = "ag-k8s"
  location                     = "${azurerm_resource_group.k8s.location}"
  resource_group_name          = "${azurerm_resource_group.k8s.name}"
    depends_on = ["azurerm_public_ip.pip_appgateway",
                  "azurerm_subnet.appgateway_subnet"
                ]
  sku {
    name     = "WAF_Medium"
    tier     = "WAF"
    capacity = 1
  }

  waf_configuration {
    enabled          = "true"
    firewall_mode    = "Detection"
    rule_set_type    = "OWASP"
    rule_set_version = "3.0"
  }

  gateway_ip_configuration {
    name      = "subnet"
    subnet_id                     = "${azurerm_subnet.appgateway_subnet.id}"
  }

  frontend_port {
    name = "http"
    port = 80
  }

  frontend_ip_configuration {
    name                 = "frontend"
    public_ip_address_id = "${azurerm_public_ip.pip_appgateway.id}"
  }

  backend_address_pool {
    name        = "Coke-Guestbook-pool"
    "ip_address_list" = ["${join("", list(var.IPAddressPrefix, ".10.67"))}"]
  }
  backend_address_pool {
    name        = "Pepsi-Wordpress-pool"
    "ip_address_list" = ["${join("", list(var.IPAddressPrefix, ".10.66"))}"]
  }
  http_listener {
    name                           = "Coke-Guestbook"
    host_name                      = "cokefan.com"
    frontend_ip_configuration_name = "frontend"
    frontend_port_name             = "http"
    protocol                       = "Http"
  }

  http_listener {
    name                           = "Pepsi-WordPress"
    host_name                      = "pepsifan.com"
    frontend_ip_configuration_name = "frontend"
    frontend_port_name             = "http"
    protocol                       = "Http"
  }

  backend_http_settings {
    name                  = "http"
    cookie_based_affinity = "Disabled"
    port                  = 80
    protocol              = "Http"
    request_timeout       = 1
   # probe_name            = "probe"
  }

  request_routing_rule {
    name                       = "Pepsi-Rule"
    rule_type                  = "Basic"
    http_listener_name         = "Pepsi-Wordpress"
    backend_address_pool_name  = "Pepsi-Wordpress-pool"
    backend_http_settings_name = "http"
  }
  request_routing_rule {
    name                       = "Coke-Rule"
    rule_type                  = "Basic"
    http_listener_name         = "Coke-Guestbook"
    backend_address_pool_name  = "Coke-Guestbook-pool"
    backend_http_settings_name = "http"
  }
}





resource "azurerm_kubernetes_cluster" "k8s" {
    name                = "${var.cluster_name}"
    location            = "${var.location}"
    resource_group_name = "${var.resource_group_name}"
    dns_prefix          = "${var.dns_prefix}"

    linux_profile {
        admin_username = "${var.linux_admin_username}"

        ssh_key {
        key_data = "${file("${var.ssh_public_key}")}"
        }
    }

    agent_pool_profile {
        name            = "default"
        count           = "${var.agent_count}"
        vm_size         = "${var.k8s-vm-node}"
        os_type         = "Linux"
        os_disk_size_gb = 30
        vnet_subnet_id = "${azurerm_subnet.aks_subnet.id}"
    }

    service_principal {
        client_id     = "${var.client_id}"
        client_secret = "${var.client_secret}"
    }  
     network_profile {
     network_plugin     = "azure"
#   network_plugin     = "kubenet"
    dns_service_ip     = "10.21.0.10"
#    docker_bridge_cidr = "169.254.123.1/24"
    docker_bridge_cidr = "172.21.0.1/16"
    service_cidr       = "10.21.0.0/16"
    }
    tags {
        Environment = "k8s-PANW-HOW"
    }
}

# VM Firewall deployment  @@@@@@@@@@@@@@@@@@@@@@@@@@
  resource "azurerm_public_ip" "PublicIP_0" {
  name = "${var.fwpublicIPName}"
  location = "${var.location}"
  resource_group_name = "${azurerm_resource_group.k8s.name}"
  public_ip_address_allocation = "${var.publicIPAddressType}"
  domain_name_label = "${join("", list(var.FirewallDnsName, substr(md5(azurerm_resource_group.k8s.id), 0, 4)))}"
}

resource "azurerm_public_ip" "PublicIP_1" {
  name = "${var.WebPublicIPName}"
  location = "${var.location}"
  resource_group_name = "${azurerm_resource_group.k8s.name}"
  public_ip_address_allocation = "${var.publicIPAddressType}"
  domain_name_label = "${join("", list(var.WebServerDnsName, substr(md5(azurerm_resource_group.k8s.id), 0, 4)))}"
}
resource "azurerm_storage_account" "PANFW-k8s-STG_ACCT" {
  name = "${join("", list(var.StorageAccountName, substr(md5(azurerm_resource_group.k8s.id), 0, 4)))}"
  resource_group_name = "${azurerm_resource_group.k8s.name}"
  location = "${var.location}"
  account_tier = "${var.storageAccountTier}"
  account_replication_type = "LRS"
  account_tier = "Standard" 
}
resource "azurerm_network_interface" "VNIC0" {
  name                = "${join("", list("FW", var.nicName, "0"))}"
  location            = "${var.location}"
  resource_group_name = "${azurerm_resource_group.k8s.name}"
  depends_on          = ["azurerm_virtual_network.aks_advanced_network",
                          "azurerm_public_ip.PublicIP_0"]

  ip_configuration {
    name                          = "${join("", list("ipconfig", "0"))}"
    subnet_id                     = "${azurerm_subnet.mgmt_subnet.id}"
    private_ip_address_allocation = "static"
    private_ip_address = "${join("", list(var.IPAddressPrefix, ".0.4"))}"
    public_ip_address_id = "${azurerm_public_ip.PublicIP_0.id}"
  }

  tags {
    displayName = "${join("", list("NetworkInterfaces", "0"))}"
  }
}

resource "azurerm_network_interface" "VNIC1" {
  name                = "${join("", list("FW", var.nicName, "1"))}"
  location            = "${var.location}"
  resource_group_name = "${azurerm_resource_group.k8s.name}"
  depends_on          = ["azurerm_virtual_network.aks_advanced_network"]

  enable_ip_forwarding = true
  ip_configuration {
    name                          = "${join("", list("ipconfig", "1"))}"
    subnet_id                     = "${azurerm_subnet.untrust_subnet.id}"
    private_ip_address_allocation = "static"
    private_ip_address = "${join("", list(var.IPAddressPrefix, ".1.4"))}"
    public_ip_address_id = "${azurerm_public_ip.PublicIP_1.id}"
  }

  tags {
    displayName = "${join("", list("NetworkInterfaces", "1"))}"
  }
}

resource "azurerm_network_interface" "VNIC2" {
  name                = "${join("", list("FW", var.nicName, "2"))}"
  location            = "${var.location}"
  resource_group_name = "${azurerm_resource_group.k8s.name}"
  depends_on          = ["azurerm_virtual_network.aks_advanced_network"]

  enable_ip_forwarding = true
  ip_configuration {
    name                          = "${join("", list("ipconfig", "2"))}"
    subnet_id                     = "${azurerm_subnet.trust_subnet.id}"
    private_ip_address_allocation = "static"
    private_ip_address = "${join("", list(var.IPAddressPrefix, ".2.4"))}"
  }

  tags {
    displayName = "${join("", list("NetworkInterfaces", "2"))}"
  }
}

resource "azurerm_virtual_machine" "PAN_k8s_FW" {
  name                  = "${var.FirewallVmName}"
  location              = "${var.location}"
  resource_group_name   = "${azurerm_resource_group.k8s.name}"
  vm_size               = "${var.FirewallVmSize}"

  depends_on = ["azurerm_network_interface.VNIC0",
                "azurerm_network_interface.VNIC1",
                "azurerm_network_interface.VNIC2"
                ]
  plan {
    name = "${var.fwSku}"
    publisher = "${var.fwPublisher}"
    product = "${var.fwOffer}"
  }

  storage_image_reference {
    publisher = "${var.fwPublisher}"
    offer     = "${var.fwOffer}"
    sku       = "${var.fwSku}"
    version   = "latest"
  }

  storage_os_disk {
    name          = "${join("", list(var.FirewallVmName, "-osDisk"))}"
    vhd_uri       = "${azurerm_storage_account.PANFW-k8s-STG_ACCT.primary_blob_endpoint}vhds/${var.FirewallVmName}-${var.fwOffer}-${var.fwSku}.vhd"
    caching       = "ReadWrite"
    create_option = "FromImage"
  }

  os_profile {
    computer_name  = "${var.FirewallVmName}"
    admin_username = "${var.adminUsername}"
    admin_password = "${var.adminPassword}"
    custom_data = "${var.customdata}"
  }

  primary_network_interface_id = "${azurerm_network_interface.VNIC0.id}"
  network_interface_ids = ["${azurerm_network_interface.VNIC0.id}",
                           "${azurerm_network_interface.VNIC1.id}",
                           "${azurerm_network_interface.VNIC2.id}",
                          ]

  os_profile_linux_config {
    disable_password_authentication = false
  }
}



