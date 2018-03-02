# 3-tier MAIN.tf
#
# Shmuel tests
#
#############################################
#Define the providers to use
#############################################

provider "ibm" {
  softlayer_username = "${var.ibm_sl_username}"
  softlayer_api_key = "${var.ibm_sl_api_key}"
}

########################################################
#Create SSH key for VSIs (VMs)
########################################################

resource "ibm_compute_ssh_key" "ssh_key" {
  label = "${var.ssh_label}"
  notes = "${var.ssh_notes}"
#  public_key = "${var.ssh_key}"
    public_key                  = "${var.ssh_public_key}"
}


##################################################
# DC & router variables
##################################################
variable "ibm_sl_username" {
  default = "shmuel"
  description = "the SoftLayer user name"
}
variable "ibm_sl_api_key" {
  default = ""
  description = "the SoftLayer api key"
}


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
variable "port" {
   default = "9443"
   description = "load balancer port"
}
####################################################
# Create the public VLAN and subnet
# for the web tier
####################################################
resource "ibm_network_vlan" "vlan_public" {
   name = "3tier_public"
   datacenter = "${var.datacenter}"
   type = "PUBLIC"
   subnet_size = 8
   router_hostname = "${var.public_router}"
}
resource "ibm_subnet" "public_subnet" {
  type = "Portable"
  private = false
  ip_version = 4
  capacity = 8
  public_vlan_id = "${ibm_network_vlan.vlan_public.id}"
  notes = "portable_public_subnet"
}

####################################################
# Create the private VLAN and two subnets
# for the app tier
####################################################

resource "ibm_network_vlan" "vlan_private" {
   name = "3tier_private"
   datacenter = "${var.datacenter}"
   type = "PRIVATE"
   subnet_size = 8
   router_hostname = "${var.private_router}"
}

resource "ibm_subnet" "apptier_subnet1" {
  type = "Portable"
  private = true
  ip_version = 4
  capacity = 8
  private_vlan_id = "${ibm_network_vlan.vlan_private.id}"
  notes = "portable_private_web__subnet"
}

resource "ibm_subnet" "apptier_subnet2" {
  type = "Portable"
  private = true
  ip_version = 4
  capacity = 8
  private_vlan_id = "${ibm_network_vlan.vlan_private.id}"
  notes = "portable_private_APP__subnet"
}
#------------------------------------

##############################################################################
# Create the web tier VMs that will be part of the LB service group
##############################################################################
resource "ibm_compute_vm_instance" "webtiervm" {
  count = "${var.vm_count}"
  os_reference_code = "${var.osrefcode}"
  hostname = "${format("webtier-%02d", count.index + 1)}"
  domain = "${var.domain}"
  datacenter = "${var.datacenter}"
  file_storage_ids = "${var.webfileid}"
  network_speed = 10
  cores = 1
  memory = 1024
  local_disk = true
  ssh_key_ids = ["${ibm_compute_ssh_key.ssh_key.id}"]
  local_disk = false
  private_vlan_id = "${var.private_vlan_id}"
  public_vlan_id = "${var.public_vlan_id}"
  private_subnet = "${var.private_vlan_subnet1_id}"
}

##############################################################################
# Create the APP tier VMs that will be part of the LB service group
##############################################################################
resource "ibm_compute_vm_instance" "apptiervm" {
  count = "${var.vm_count}"
  os_reference_code = "${var.osrefcode}"
  hostname = "${format("apptier-%02d", count.index + 1)}"
  datacenter = "${var.datacenter}"
  file_storage_ids = ["${var.appfileid}"]
  block_storage_ids = ["${var.appblockid}"]
  network_speed = 10
  cores = 1
  memory = 1024
  disks = [25, 10]
  ssh_key_ids = ["${ibm_compute_ssh_key.ssh_key.id}"]
  local_disk = false
  private_vlan_id = "${var.vlan_private_id}"
  private_subnet = "${var.private_vlan_subnet2_id}"
# this is where we add the security group #
}


##############################################################################
# variables
##############################################################################
variable domain {
  description = "domain of the VMs"
  default = "mybluemix.com"
}
variable privatevlanid {
  description = "private VLAN"
  default = "123456"
}
variable publicvlanid {
  description = "public VLAN"
  default = "123456"
}

variable ssh_public_key {
  default = "please fill in"
}
variable ssh_label {
  default = "3-tiersshkey"
}
variable ssh_notes {
  default = "this is the 3 tier example ssh key"
}
variable node_count {
  default = "1"
}
variable osrefcode {
  default = "UBUNTU_LATEST"
}
variable vm_count {
  default = "1"
}
################################################
# Outputs
################################################
  output "app_ipaddress" {
  value = "[${ibm_compute_vm_instance.apptiervm.ip_address_id}]"
}
  output "web_ipaddress" {
  value = "[${ibm_compute_vm_instance.webtiervm.ip_address_id}]"
}
#----------------------------------------

##############################################################################
# Create a local loadbalancer (ToDo:  replace hard coded values)
##############################################################################
resource "ibm_lb" "lb" {
    connections = 1500
    datacenter = "${var.datacenter}"
    ha_enabled = false
    dedicated = false       
}

##############################################################################
# Create a service group in the loadbalancer
##############################################################################
resource "ibm_lb_service_group" "lb_service_group" {
  port                        = "${var.service_group_port}"
  routing_method              = "${var.service_group_routing_method}"
  routing_type                = "${var.service_group_routing_type}"
  load_balancer_id            = "${ibm_lb.lb.id}"
  allocation                  = "${var.service_group_allocation}"
}

##############################################################################
# Create a service
# Defines a service for each node; determines the health check,
# load balancer weight, and ip the loadbalancer will send traffic to
##############################################################################
resource "ibm_lb_service" "web_lb_service" {
  # The number of services to create, based on web node count
  count                       = "${var.vm_count}"
  # port to serve traffic on
  port                        = "${var.port}"
  enabled                     = true
  service_group_id            = "${ibm_lb_service_group.lb_service_group.service_group_id}"
  # Even distribution of traffic
  weight                      = 1
  # Uses HTTP to as a healthcheck
  health_check_type           = "HTTP"
  # Where to send traffic to
  ip_address_id               = "${element(web_ipaddress, count.index)}"
  # For demonstration purposes; creates an explicit dependency
  depends_on                  = ["ibm_compute_vm_instance.node"]
}

resource "ibm_lb_service" "app_lb_service" {
  # The number of services to create, based on web node count
  count                       = "${var.node_count}"
  # port to serve traffic on
  port                        = "${var.port}"
  enabled                     = true
  service_group_id            = "${ibm_lb_service_group.lb_service_group.service_group_id}"
  # Even distribution of traffic
  weight                      = 1
  # Uses HTTP to as a healthcheck
  health_check_type           = "HTTP"
  # Where to send traffic to
  ip_address_id               = "${element(app_ipaddress, count.index)}"
  # For demonstration purposes; creates an explicit dependency
  depends_on                  = ["web_ipaddress", "app_ipaddress"]
}

#################################################
# File Storage
#################################################

resource "ibm_storage_file" "webtierfile" {
  type = "Performance"
  datacenter = "${var.datacenter}"
  capacity = "20"
  iops = "100"
}

resource "ibm_storage_file" "apptierfile" {
  type = "Performance"
  datacenter = "${var.datacenter}"
  capacity = "20"
  iops = "100"
}
#################################################
# Block Storage
#################################################

resource "ibm_storage_block" "apptierblock" {
        type = "Performance"
        datacenter = "${var.datacenter}"
        capacity = 20
        iops = 100
        os_format_type = "Linux"
}
resource "ibm_storage_block" "datatierblock" {
        type = "Performance"
        datacenter = "${var.datacenter}"
        capacity = 20
        iops = 100
        os_format_type = "Linux"
}


#####################################################
# Output reused as Variables
#####################################################
output "vlan_datacenter" {
  value = ["${var.datacenter}"]
}
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
################################################
# Storage Output variables
################################################
output "webfileid" {
  value = "${ibm_storage_file.webtierfile.id}"
}
output "appfileid" {
  value = "${ibm_storage_file.apptierfile.id}"
}
output "appblockid" {
  value = "${ibm_storage_block.apptierblock.id}"
}
output "datablockid" {
  value = "${ibm_storage_block.datatierblock.id}"
}

