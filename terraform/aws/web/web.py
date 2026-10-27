import os
import requests
from flask import Flask, jsonify

app = Flask(__name__)


# Health check: the load balancer calls this to decide if the container is alive.
@app.route("/health")
def health():
    return jsonify(status="ok")


# Home page: calls the app tier's /db route and shows which cloud served the request.
@app.route("/")
def home():
    app_url = os.environ["APP_URL"]                  # where the app tier lives (set by Terraform)
    cloud = os.environ.get("CLOUD_NAME", "AWS")      # shown in the response, handy for the failover drill
    response = requests.get(f"{app_url}/db", timeout=5)
    return f"Served by: {cloud} | App tier says: {response.text}"


# Must stay LAST: Flask only knows routes defined before app.run().
if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)