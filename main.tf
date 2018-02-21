# 3-tier MAIN.tf
# No modules
#
#############################################
#Define the providers to use
#############################################

provider "ibm" {
  softlayer_username = "${var.ibm_sl_username}"
  softlayer_api_key = "${var.ibm_sl_api_key}"
}

########################################################
#Create SSH key for VSIs
########################################################

resource "ibm_compute_ssh_key" "ssh_key" {
  label = "${var.ssh_label}"
  notes = "${var.ssh_notes}"
  public_key = "${var.ssh_key}"
}

#####################################################
# Variables
#####################################################


variable "datacenter" {
  default = "dal13"
  description = "the data center to deploy the VLAN."
}
variable "public_router" {
  default = "fcr01a.dal13"
  description = "the router to use for the public VLAN."
}
variable "private_router" {
  default = "bcr01a.dal13"
  description = "the router to use for the private VLAN."
}

#####################################################
# Output reused as Variables
#####################################################

output "public_vlan_id" {
  value = "${ibm_network_vlan.vlan_public.id}"
}
output "public_vlan_subnet_id" {
  value = "${ibm_subnet.webtier_subnet.id}"
}
output "private_vlan_id" {
  value = "${ibm_network_vlan.vlan_private.id}"
}
output "private_vlan_subnet1_id" {
  value = "${ibm_subnet.apptier_subnet1.id}"
}
output "private_vlan_subnet2_id" {
  value = "${ibm_subnet.apptier_subnet2.id}"
}
