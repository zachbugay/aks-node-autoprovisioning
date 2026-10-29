terraform {
  required_version = ">= 1.5"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
  }
}

provider "azurerm" {
  features {}
}

variable "resource_group_name" {
  type    = string
  default = "rg-aks-nap-demo"
}

variable "location" {
  type    = string
  default = "eastus"
}

variable "cluster_name" {
  type    = string
  default = "aks-nap-demo"
}

variable "kubernetes_version" {
  type    = string
  default = "1.36"
}

resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
}

resource "azurerm_resource_group" "capacity_reservations" {
  name     = "${var.resource_group_name}-capacity"
  location = var.location
}

resource "azurerm_user_assigned_identity" "aks" {
  name                = "${var.cluster_name}-identity"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  tags = {
    environment = "demo"
    feature     = "NAP"
  }
}

resource "azurerm_virtual_network" "main" {
  name                = "vnet-aks-nap"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  address_space = ["10.10.0.0/22"]
}

resource "azurerm_subnet" "system_nodes" {
  name                 = "snet-aks-system"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name

  address_prefixes = ["10.10.0.0/27"]
}

resource "azurerm_subnet" "workload_nodes" {
  name                 = "snet-aks-workload"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name

  address_prefixes = ["10.10.1.0/24"]
}

resource "azurerm_kubernetes_cluster" "main" {
  name                = var.cluster_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  dns_prefix          = var.cluster_name
  kubernetes_version  = var.kubernetes_version

  sku_tier = "Standard"

  # Docs say user assigned is required, not system. Not sure why, need to test
  # https://github.com/Azure/karpenter-provider-azure/blob/main/docs/capacity-reservations.md

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.aks.id]
  }

  node_provisioning_profile {
    mode = "Auto"
  }

  default_node_pool {
    name           = "system"
    node_count     = 1
    vm_size        = "Standard_D4ds_v6"
    vnet_subnet_id = azurerm_subnet.system_nodes.id

    # Taint system nodes so workloads don't schedule here on system node pool
    only_critical_addons_enabled = true

    upgrade_settings {
      max_surge = "33%"
    }
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_data_plane  = "cilium"
    load_balancer_sku   = "standard"
    pod_cidr            = "192.168.0.0/16"
    service_cidr        = "10.0.0.0/16"
    dns_service_ip      = "10.0.0.10"
  }

  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  automatic_upgrade_channel = "patch"

  depends_on = [
    azurerm_role_assignment.network_contributor,
    azurerm_role_assignment.contributor
  ]

  tags = {
    environment = "demo"
    feature     = "NAP"
  }
}

resource "azurerm_role_assignment" "network_contributor" {
  scope                = azurerm_virtual_network.main.id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.aks.principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "contributor" {
  scope                = azurerm_resource_group.capacity_reservations.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_user_assigned_identity.aks.principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_capacity_reservation_group" "nap" {
  name                = "${var.cluster_name}-crg"
  resource_group_name = azurerm_resource_group.capacity_reservations.name
  location            = azurerm_resource_group.capacity_reservations.location
}

resource "azurerm_capacity_reservation" "d4ads_v6" {
  name                          = "${var.cluster_name}-d4ads-v6"
  capacity_reservation_group_id = azurerm_capacity_reservation_group.nap.id

  sku {
    name     = "Standard_D4ads_v6"
    capacity = 1
  }
}

output "workload_subnet_id" {
  value = azurerm_subnet.workload_nodes.id
}

output "cluster_id" {
  value = azurerm_kubernetes_cluster.main.id
}

output "capacity_reservation_group_id" {
  value = azurerm_capacity_reservation_group.nap.id
}
