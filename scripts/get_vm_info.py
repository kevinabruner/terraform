
import requests
import os
import shutil
import ipaddress
import requests

 
def get_gateway(ip_string): 
    ip_network = ipaddress.ip_network(ip_string, strict=False)
    # Check if the IP address is in the correct format (e.g., 192.168.x.x/24)
    if ip_network.version == 4:
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
            
            # Copy and rename the template files
            shutil.copy(gitDir + '/main.template', curDir + '/main.tf')
            shutil.copy(os.path.join(gitDir, 'vars.template'), os.path.join(curDir, 'vars.tf'))            
                        
            #adds a line for each VM as a sub-module in the main module's configuration file             
            moduleLine = "module \"" + vm["name"] + "\" { source = \"/home/kevin/terraform/vms/" + vm["name"] + "\" }"
            with open(gitDir + '/main.tf', 'a') as file:
                file.write(moduleLine + '\n')                
            
            #get the interface and then it's mac address
            interface = et_phone_home('http://netbox.thejfk.ca/api/virtualization/interfaces/' + str(vm["id"])
            print(interface)
            mac_address = interface['mac_address']
                                                        
            #counts of 1 for active, zero for everything else
            if vm['status']['value'] == 'active':
                replace_text_in_file(curDir + "/main.tf" , "@@@count", "1")   
            else:
                replace_text_in_file(curDir + "/main.tf" , "@@@count", "0")   
            
            ###adds a line if NFS is needed
            if vm["custom_fields"]["nfs"]:
                replace_text_in_file(curDir + "/main.tf" , "@@@nfs", "mount = \"nfs\"")   
            else:
                replace_text_in_file(curDir + "/main.tf" , "@@@nfs", "")               
            
            ###adds a line if there is a vlan tag
            if vm["custom_fields"]["vlan"]:                
                vlanId = str(vm["custom_fields"]["vlan"][0]['vid'])                
                replace_text_in_file(curDir + "/main.tf" , "@@@vlan", "tag = \"" + vlanId + "\"")   
            else:
                replace_text_in_file(curDir + "/main.tf" , "@@@vlan", "")               

            ###generic variable replacements
            replace_text_in_file(curDir + "/vars.tf" , "@@@curDir", curDir)            
            replace_text_in_file(curDir + "/vars.tf" , "@@@vm_macaddr", mac_address)
            replace_text_in_file(curDir + "/vars.tf" , "@@@vm_gw", get_gateway(vm["primary_ip4"]["address"]))
            replace_text_in_file(curDir + "/main.tf" , "@@@vm_name", vm["name"])
            replace_text_in_file(curDir + "/vars.tf" , "@@@vm_name", vm["name"])
            replace_text_in_file(curDir + "/vars.tf" , "@@@unpriv", str(vm["custom_fields"]["unpriv"]).lower())
            replace_text_in_file(curDir + "/vars.tf" , "@@@vmid", vm["custom_fields"]["vmid"])                                    
            replace_text_in_file(curDir + "/vars.tf" , "@@@vm_ip", vm["primary_ip4"]["address"])
            replace_text_in_file(curDir + "/vars.tf" , "@@@pve_node", vm["device"]["name"])
            replace_text_in_file(curDir + "/vars.tf" , "@@@cores", str(vm["vcpus"]))
            replace_text_in_file(curDir + "/vars.tf" , "@@@memory", str(vm["memory"]))
            replace_text_in_file(curDir + "/vars.tf" , "@@@storage", str(vm["disk"]))

        
        
                


