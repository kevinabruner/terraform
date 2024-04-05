
import requests
import os
import shutil


def truncate_file_after_marker(file_path, marker):
    try:
        with open(file_path, 'r+') as file:
            # Find the position of the marker
            file_content = file.read()
            marker_index = file_content.find(marker)

            # If the marker is found, truncate the file from that position onwards
            if marker_index != -1:
                file.seek(marker_index)
                file.truncate()

        print(f"File '{file_path}' truncated after marker '{marker}'")
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
            os.makedirs(curDir)        

        shutil.copy(gitDir + '/main.template', curDir)
        shutil.copy(gitDir + '/vars.template', curDir)        

        
        moduleLine = "module \"test\" { source = \"/home/kevin/terraform/vms/" + result["name"] + "\" }"
        with open(gitDir + '/main.tf', 'a') as file:
            file.write(moduleLine + '\n')


        replace_text_in_file(curDir + "/main.template" , "@@@vm_name", result["name"])
        replace_text_in_file(curDir + "/vars.template" , "@@@vm_name", result["name"])
        replace_text_in_file(curDir + "/vars.template" , "@@@vm_ip", result["primary_ip4"]["address"].split("/")[0])
        replace_text_in_file(curDir + "/vars.template" , "@@@pve_node", result["device"]["name"])
        replace_text_in_file(curDir + "/vars.template" , "@@@cores", str(result["vcpus"]))
        replace_text_in_file(curDir + "/vars.template" , "@@@memory", str(result["memory"]))
        replace_text_in_file(curDir + "/vars.template" , "@@@storage", str(result["disk"]))

        
        
                


