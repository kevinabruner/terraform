# Terraform

This repository has been updated to be far less shit than it once was. 

## General notes

- This repository uses [my local Netbox instance](https://netbox.thejfk.ca/) as a source of truth. 
- VMs are located in [my Proxmox Cluster](https://pve.thejfk.ca).

## Installation

An [installation script](scripts/install.sh) is included in this repo. I try not to re-install this very often for obvious reasons, so use at your own risk. 

## Plugins
It uses the following plugins:
- [`e-breuninger/netbox`](https://github.com/e-breuninger/terraform-provider-netbox): This allows for direct connection to Netbox using a local `main.tf` file in this repo. This plugin pulls variables from the VM data in [my local Netbox instance](https://netbox.thejfk.ca/).
- [`telmate/proxmox`](): This is the main Terraform plugin for managing Proxmox intances.

## Secrets, passwords, tokens and SSH Keys
- Permitted SSH Keys (admin side as well as ansible control) are located in the [Config Contexts](https://netbox.thejfk.ca/extras/config-contexts/1/) page of Netbox. If you change admin hosts or ansible controllers, update accordigly
- Tokens, passwords and secrets are currently stored in /etc/environment on the terraform controller and are managed manually. Hopefully one day this will change, but I suspect not before you come back here to read this.
    - All of these env variables are protyped in [vars.tf](./vars.tf) if you need to consult their name or datatype.