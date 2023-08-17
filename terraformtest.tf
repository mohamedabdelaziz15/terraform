terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      version = "3.67.0"
    }
  }
}

provider "azurerm" {
    subscription_id = "b779ae05-e2b8-48c7-918c-71d70b38134b"
    client_id = "53def8f7-de16-451e-bb27-5bfb0d3c82d7"
    client_secret = "11e8Q~nsB~6hXd6yty7IisZQGlJRKGEi2SYhHbBH"
    tenant_id = "fda58d33-7098-40bb-8d52-891d51bb65e0"
    features {}
}

resource "azurerm_resource_group" "resource_group" {     # Define Resource Group Name and Location
  name = "rg-terra-test" 
  location = "East US"
}

resource "azurerm_storage_account" "storage_account" {
    name = "blob02terra0test"
    resource_group_name = azurerm_resource_group.resource_group.name
    location = azurerm_resource_group.resource_group.location
    account_tier = "Standard"
    account_replication_type = "LRS"
    is_hns_enabled = true
    allow_nested_items_to_be_public = true

  depends_on = [ azurerm_resource_group.resource_group ]
}

resource "azurerm_storage_container" "storage_container" {
    name = "bronzelayer"
    storage_account_name = azurerm_storage_account.storage_account.name
    container_access_type = "private"

    depends_on = [ azurerm_storage_account.storage_account ]
}

resource "azurerm_data_factory" "data_factory" {
  name                = "adfterra02test"
  location            = azurerm_resource_group.resource_group.location
  resource_group_name = azurerm_resource_group.resource_group.name
}

resource "azurerm_data_factory_linked_service_azure_blob_storage" "adf_ls_blob" {
  name = "LS-BLOB-ADF"
  data_factory_id = azurerm_data_factory.data_factory.id
  connection_string = azurerm_storage_account.storage_account.primary_connection_string
}

resource "azurerm_data_factory_dataset_parquet" "DS-PARQUET" {
  name = "DS-PAQRUET-ADF"
  data_factory_id = azurerm_data_factory.data_factory.id
  linked_service_name = azurerm_data_factory_linked_service_azure_blob_storage.adf_ls_blob.name

  azure_blob_storage_location {
    container = azurerm_storage_container.storage_container.name
  }
}

resource "azurerm_databricks_workspace" "databricks" {
  name = "dbterra02test"
  resource_group_name = azurerm_resource_group.resource_group.name
  location = azurerm_resource_group.resource_group.location
  sku = "standard"
}

resource "azurerm_storage_data_lake_gen2_filesystem" "terraform_file_System" {  #Create File System Name for Synapse Workspace
  name               = "filesystem"
  storage_account_id = azurerm_storage_account.storage_account.id

  depends_on = [ azurerm_storage_account.storage_account ]
}

resource "azurerm_synapse_workspace" "synapse_workspace" {   #Create Workspace Name
  name                                 = "synterratest02"
  resource_group_name                  = azurerm_resource_group.resource_group.name
  location                             = azurerm_resource_group.resource_group.location
  storage_data_lake_gen2_filesystem_id = azurerm_storage_data_lake_gen2_filesystem.terraform_file_System.id

  sql_administrator_login              = "sqladminuser"
  sql_administrator_login_password     = "Orion@360"

  aad_admin {
    login     = "AzureAD Admin"
    object_id = "32d61dfe-af50-4b3a-a88c-72ac592e5d77"
    tenant_id = "2f4a9838-26b7-47ee-be60-ccc1fdec5953"
  }
 
  identity {
    type = "SystemAssigned"
  }

  depends_on = [ azurerm_storage_data_lake_gen2_filesystem.terraform_file_System ]
}

resource "azurerm_synapse_firewall_rule" "firewall_rule" {   #Disabling Public Network Access
  name                 = "AllowAll"
  synapse_workspace_id = azurerm_synapse_workspace.synapse_workspace.id
  start_ip_address     = "0.0.0.0"
  end_ip_address       = "255.255.255.255"

  depends_on = [ azurerm_synapse_workspace.synapse_workspace]

}

resource "azurerm_synapse_role_assignment" "role_assignment" {
  synapse_workspace_id = azurerm_synapse_workspace.synapse_workspace.id
  role_name            = "Synapse Administrator"
  principal_id         = "32d61dfe-af50-4b3a-a88c-72ac592e5d77"

  depends_on = [ azurerm_synapse_firewall_rule.firewall_rule ]

}

resource "azurerm_synapse_linked_service" "linked_service" {
  name                 = "LS_AZURE_BLOB"
  synapse_workspace_id = azurerm_synapse_workspace.synapse_workspace.id
  type                 = "AzureBlobStorage"
  type_properties_json = <<JSON
{
  "connectionString": "${azurerm_storage_account.storage_account.primary_connection_string}"
}
JSON
  depends_on = [
    azurerm_synapse_firewall_rule.firewall_rule,
  ]
}