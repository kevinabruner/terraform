
import requests

# Set your token
TOKEN = "18a09ac581f3b2679df0f538698e2893aac493a7"

# Define the URL
url = "https://netbox.thejfk.ca/api/ipam/ip-addresses/?limit=1000"

# Set the headers
headers = {
    "Authorization": f"Token {TOKEN}",
    "Accept": "application/json; indent=4"
}

# Send the GET request
response = requests.get(url, headers=headers)

data = response.json()

output = {"vm_results": []}

for result in data["results"]:
    if result["primary_ip4"]:
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
        output["vm_results"].append(vm_results)


print(output)

# Write the output to a JSON file
#with open("output.json", "w") as outfile:
#    json.dump(output, outfile, indent=4)
