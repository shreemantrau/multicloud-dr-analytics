import os

import google.auth.transport.requests
import google.oauth2.id_token
import requests
from flask import Flask

app = Flask(__name__)


@app.route("/health")
def health():
    return {"status": "ok"}


@app.route("/")
def index():
    app_url = os.environ["APP_URL"]
    cloud = os.environ.get("CLOUD_NAME", "GCP")

    # The app service is private: Cloud Run only accepts callers that present a Google-signed
    # ID token for that service. The web tier's service account gets one from the metadata server.
    token = google.oauth2.id_token.fetch_id_token(
        google.auth.transport.requests.Request(), app_url
    )
    response = requests.get(
        f"{app_url}/db", headers={"Authorization": f"Bearer {token}"}, timeout=5
    )
    return f"Served by: {cloud} | App tier says: {response.text}"


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)