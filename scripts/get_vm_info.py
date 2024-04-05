
import requests
import os
import shutil

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

for result in data["results"]:    
    if result["primary_ip4"]:
        curDir = gitDir + '/vms/' + result["name"]
        
        shutil.rmtree(curDir)            
        os.makedirs(curDir)        

        shutil.copy(gitDir + '/main-template.tf', curDir)
        shutil.copy(gitDir + '/vars-template.tf', curDir)

        vm_results = {
            "ip": result["primary_ip4"]["address"].split("/")[0],
            "name": result["name"],
            "host": {
                "name": result["device"]["name"],
                "id": result["device"]["id"],
            },
            "hardware": {
                "vcpus": result["vcpus"],
                "memory": result["memory"],
                "disk": result["disk"],
            }
        }
        all_vms["vm_results"].append(vm_results)

print(all_vms)

