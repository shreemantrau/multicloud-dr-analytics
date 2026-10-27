import os
import json

import boto3
import psycopg2
from flask import Flask, jsonify

app = Flask(__name__)


# Health check: the load balancer calls this to decide if the container is alive.
@app.route("/health")
def health():
    return jsonify(status="ok")


# DB test: proves the full chain (task role -> Secrets Manager -> RDS) works.
@app.route("/db")
def db():
    # Settings come from environment variables that Terraform sets on the ECS task.
    secret_id = os.environ["DB_SECRET_ID"]
    region = os.environ.get("AWS_REGION", "us-west-2")

    # boto3 finds credentials by itself: inside ECS it uses the task role (no keys anywhere).
    client = boto3.client("secretsmanager", region_name=region)
    secret = json.loads(client.get_secret_value(SecretId=secret_id)["SecretString"])
    password = secret["password"]
    # Connect to the private RDS endpoint and run the simplest possible query.
    conn = psycopg2.connect(
        host=os.environ["DB_HOST"],
        dbname=os.environ["DB_NAME"],
        user=os.environ["DB_USER"],
        password=password,
        # RDS only accepts encrypted connections, so require SSL up front instead of trying plain text first.
        sslmode="require",
        connect_timeout=5,
    )
    cur = conn.cursor()
    cur.execute("SELECT 1")
    result = cur.fetchone()[0]
    conn.close()
    return jsonify(db_result=result)


# Must stay LAST: Flask only knows routes defined before app.run().
if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)