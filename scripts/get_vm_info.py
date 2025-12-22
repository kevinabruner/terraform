
import requests
import os
import shutil
import ipaddress
import requests

def get_gateway(ip_string): 
    ip_network = ipaddress.ip_network(ip_string, strict=False)    
    parts = ip_string.split('.')        
    gateway = f"{parts[0]}.{parts[1]}.{parts[2]}.1"
    return gateway

def truncate_file_after_marker(file_path, marker):
    try:
        with open(file_path, 'r+') as file:
            lines = file.readlines()
            marker_index = -1

            # Find the marker line
            for i, line in enumerate(lines):
                if marker in line:
                    marker_index = i
                    break

            # If the marker line is found, truncate the file after that line
            if marker_index != -1:
                file.seek(0)
                file.truncate()
                file.writelines(lines[:marker_index+1])

        print(f"File '{file_path}' truncated after marker line '{marker}'")
    except FileNotFoundError:
        print(f"File '{file_path}' not found.")
    except Exception as e:
        print(f"An error occurred: {e}")


def replace_text_in_file(file_path, old_text, new_text):
    # Read the content of the file
    with open(file_path, 'r') as file:
        file_content = file.read()

    # Replace the old text with the new text
    modified_content = file_content.replace(old_text, new_text)

    # Write the modified content back to the file
    with open(file_path, 'w') as file:
        file.write(modified_content)

def et_phone_home(url):
    # Set your token
    TOKEN = "18a09ac581f3b2679df0f538698e2893aac493a7"    

    # Set the headers
    headers = {
        "Authorization": f"Token {TOKEN}",
        "Accept": "application/json; indent=4"
    }
    # Send the GET request
    response = requests.get(url, headers=headers)
    return response.json()

#define the terraform directory and empty the terraform configuration file
gitDir="/home/kevin/terraform"
truncate_file_after_marker(gitDir + '/main.tf', '###generated###')
   
#ensure that the working directory exists and is empty
workingDir= gitDir + '/vms'
if os.path.exists(workingDir):
    shutil.rmtree(workingDir)                
os.mkdir(workingDir)

#gets a json object of all the vms
vms = et_phone_home("https://netbox.thejfk.ca/api/virtualization/virtual-machines/?limit=1000")

#iterates through the vms
for vm in vms["results"]:    
    if vm["primary_ip4"]:
        curDir = gitDir + '/vms/' + vm["name"]
 
        if os.path.exists(curDir):
            shutil.rmtree(curDir)
                     
        os.mkdir(curDir)                                    

        if vm["custom_fields"]['VMorContainer'][0] == "vm":
            print(vm["name"])
            
            # Copy and rename the template files
            shutil.copy(gitDir + '/main.template', curDir + '/main.tf')
            shutil.copy(os.path.join(gitDir, 'vars.template'), os.path.join(curDir, 'vars.tf'))            
                        
            #adds a line for each VM as a sub-module in the main module's configuration file             
            moduleLine = "module \"" + vm["name"] + "\" { source = \"/home/kevin/terraform/vms/" + vm["name"] + "\" }"
            with open(gitDir + '/main.tf', 'a') as file:
                file.write(moduleLine + '\n')    

                         
            #counts of 1 for active, zero for everything else
            if vm['status']['value'] == 'active':
                replace_text_in_file(curDir + "/main.tf" , "@@@count", "1")   
            else:
                replace_text_in_file(curDir + "/main.tf" , "@@@count", "0")                   
            
            ###adds a line if there is a vlan tag
            if vm["custom_fields"]["vlan"]:                
                vlanId = str(vm["custom_fields"]["vlan"][0]['vid'])                
            else:
                vlanId = "0"

            networkString = f"""network {{
                id = 0
                model = "virtio"
                bridge = "vmbr0"
                tag = {vlanId}
            }}"""

            if vm["custom_fields"]["FAST_IP"]:
                networkString += """\nnetwork {
                    id = 1
                    model = "virtio"
                    bridge = "vmbr3"                    
                }"""
                
                ip_addr = vm["custom_fields"]["FAST_IP"]["address"]
                fast_ip_text = f'ipconfig1 = "ip={ip_addr}"'
                replace_text_in_file(curDir + "/main.tf", "@@@fastip", fast_ip_text)

            else:                
                replace_text_in_file(curDir + "/main.tf" , "@@@fastip", "")       

            
            ###adds a line if there is a pool tag
            if vm["custom_fields"]["proxmox_pool"]:                         
                vlanId = str(vm["custom_fields"]["proxmox_pool"])                
                replace_text_in_file(curDir + "/main.tf" , "@@@vm_pool", "pool = \"" + vm["custom_fields"]["proxmox_pool"] + "\"")   
            else:                
                replace_text_in_file(curDir + "/main.tf" , "@@@vm_pool", "")               

            # Check for the new prod_image field first
            if vm["custom_fields"].get("prod_image"):
                # If prod_image has a value, use it regardless of other settings
                image_name = str(vm["custom_fields"]["prod_image"])
                replace_text_in_file(curDir + "/main.tf", "@@@image", "clone = \"" + image_name + "\"")
            # Fallback to the existing template tag logic
            elif vm["custom_fields"].get("template"):
                templateId = str(vm["custom_fields"]["template"])
                if templateId == "ubuntu-2204-cloud":
                    templateId = "ubuntu-cloud"
                replace_text_in_file(curDir + "/main.tf", "@@@image", "clone = \"" + templateId + "\"")
            # Final fallback if neither field is set
            else:
                replace_text_in_file(curDir + "/main.tf", "@@@image", "clone = \"ubuntu-cloud\"")  

            if vm["custom_fields"].get("storage_location"):                                
                storage_location = vm["custom_fields"].get("storage_location")                      
            else:
                storage_location = "ceph"    
                
            

            if vm["disk"] >= 1000:
                diskSize = f'{int(vm["disk"] / 1000)}G'
            else:
                diskSize = f'{int(vm["disk"])}M'

            ###generic variable replacements
            replace_text_in_file(curDir + "/main.tf" , "@@@storage_location", storage_location)  
            replace_text_in_file(curDir + "/main.tf" , "@@@vm_name", vm["name"]) 
            replace_text_in_file(curDir + "/main.tf" , "@@@network", networkString)                       
            replace_text_in_file(curDir + "/vars.tf" , "@@@curDir", curDir)                        
            replace_text_in_file(curDir + "/vars.tf" , "@@@vm_gw", get_gateway(vm["primary_ip4"]["address"]))            
            replace_text_in_file(curDir + "/vars.tf" , "@@@vm_name", vm["name"])
            replace_text_in_file(curDir + "/vars.tf" , "@@@vmid", vm["custom_fields"]["vmid"])                                    
            replace_text_in_file(curDir + "/vars.tf" , "@@@vm_ip", vm["primary_ip4"]["address"])
            replace_text_in_file(curDir + "/vars.tf" , "@@@pve_node", vm["device"]["name"])
            replace_text_in_file(curDir + "/vars.tf" , "@@@cores", str(vm["vcpus"]))
            replace_text_in_file(curDir + "/vars.tf" , "@@@memory", str(vm["memory"]))
            replace_text_in_file(curDir + "/vars.tf" , "@@@storage", str(diskSize))
        
        
                


