
import requests
import os
import shutil
import ipaddress


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

# Set your token
TOKEN = "18a09ac581f3b2679df0f538698e2893aac493a7"

# Define the URL
url = "https://netbox.thejfk.ca/api/virtualization/virtual-machines/?limit=1000"

# Set the headers
headers = {
    "Authorization": f"Token {TOKEN}",
    "Accept": "application/json; indent=4"
}

gitDir="/home/kevin/terraform"

# Send the GET request
response = requests.get(url, headers=headers)

data = response.json()

all_vms = {"vm_results": []}

truncate_file_after_marker(gitDir + '/main.tf', '###generated###')



for result in data["results"]:    
    if result["primary_ip4"]:
        curDir = gitDir + '/vms/' + result["name"]
 
        if os.path.exists(curDir):
            shutil.rmtree(curDir)
                     
        os.mkdir(curDir)                                    

        if result["custom_fields"]['VMorContainer'][0] == "ct":
                    
            # Copy and rename the template files
            shutil.copy(gitDir + '/main.template', curDir + '/main.tf')
            shutil.copy(os.path.join(gitDir, 'vars.template'), os.path.join(curDir, 'vars.tf'))
            

            # adds as a module to the main.tf file only if the vm is marked as active
            if result['status']['value'] == 'active':
                moduleLine = "module \"" + result["name"] + "\" { source = \"/home/kevin/terraform/vms/" + result["name"] + "\" }"
                with open(gitDir + '/main.tf', 'a') as file:
                    file.write(moduleLine + '\n')
                
                    
            ###adds a line if NFS is needed
            if result["custom_fields"]["nfs"]:
                replace_text_in_file(curDir + "/main.tf" , "@@@nfs", "mount = \"nfs\"")   
            else:
                replace_text_in_file(curDir + "/main.tf" , "@@@nfs", "")               
            

            ###adds a line if there is a vlan tag
            if result["custom_fields"]["vlan"]:
                print(f'vlan: {result["custom_fields"]["vlan"]}')
                vlanId = str(result["custom_fields"]["vlan"]["vid"])
                
                replace_text_in_file(curDir + "/main.tf" , "@@@vlan", "tag = \"" + vlanId + "\"")   
            else:
                replace_text_in_file(curDir + "/main.tf" , "@@@vlan", "")               

            ###generic variable replacements
            replace_text_in_file(curDir + "/vars.tf" , "@@@vm_gw", get_gateway(result["primary_ip4"]["address"]))
            replace_text_in_file(curDir + "/main.tf" , "@@@vm_name", result["name"])
            replace_text_in_file(curDir + "/vars.tf" , "@@@vm_name", result["name"])
            replace_text_in_file(curDir + "/vars.tf" , "@@@unpriv", str(result["custom_fields"]["unpriv"]).lower())
            replace_text_in_file(curDir + "/vars.tf" , "@@@vmid", result["custom_fields"]["vmid"])                                    
            replace_text_in_file(curDir + "/vars.tf" , "@@@vm_ip", result["primary_ip4"]["address"])
            replace_text_in_file(curDir + "/vars.tf" , "@@@pve_node", result["device"]["name"])
            replace_text_in_file(curDir + "/vars.tf" , "@@@cores", str(result["vcpus"]))
            replace_text_in_file(curDir + "/vars.tf" , "@@@memory", str(result["memory"]))
            replace_text_in_file(curDir + "/vars.tf" , "@@@storage", str(result["disk"]))

        
        
                


