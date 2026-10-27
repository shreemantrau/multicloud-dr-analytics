import os
import psycopg2
from flask import Flask
from google.cloud import secretmanager

app = Flask(__name__)


@app.route("/health")
def health():
    return {"status": "ok"}


@app.route("/db")
def db():
    # Same pattern as Azure and AWS: the app fetches the password itself at runtime.
    # DB_SECRET_ID is the full path, e.g. projects/<project>/secrets/<name>/versions/latest.
    # The client finds credentials from the Cloud Run service account automatically.
    client = secretmanager.SecretManagerServiceClient()
    password = client.access_secret_version(
        name=os.environ["DB_SECRET_ID"]
    ).payload.data.decode("utf-8")

    conn = psycopg2.connect(
        host=os.environ["DB_HOST"],
        dbname=os.environ["DB_NAME"],
        user=os.environ["DB_USER"],
        password=password,
        connect_timeout=5,
    )
    with conn.cursor() as cur:
        cur.execute("SELECT 1")
        result = cur.fetchone()[0]
    conn.close()
    return {"db_result": result}


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)