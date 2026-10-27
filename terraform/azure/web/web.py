from flask import Flask        # Web framework
import os                      # Reads settings from environment variables
import requests                # Lets this app call the app tier over HTTP

app = Flask(__name__)

@app.route("/health")
def health():
    return "OK", 200           # Liveness check

@app.route("/")
def home():
    app_url = os.environ["APP_URL"]                      # e.g. https://app-project3-app.azurewebsites.net, set in Terraform
    r = requests.get(f"{app_url}/db", timeout=10)        # Web tier calls the app tier; timeout so it can't hang forever
    return f"Served by: Azure | App tier says: {r.text}", 200   # The "Served by" line is for the failover demo

if __name__ == "__main__":     # Must stay the LAST block in the file
    app.run(host="0.0.0.0", port=5000)