import csv
import io
import json
import os
import ssl
from urllib.parse import unquote_plus

import boto3
import pg8000.native

# Created outside the handler so warm invocations reuse them.
s3 = boto3.client("s3")
secrets = boto3.client("secretsmanager")


def handler(event, context):
    # Same pattern as the app tier: fetch the password at runtime with the Lambda's role.
    secret = json.loads(
        secrets.get_secret_value(SecretId=os.environ["DB_SECRET_ID"])["SecretString"]
    )

    # RDS Postgres 16 requires SSL. This encrypts the connection but skips certificate
    # verification, because Lambda doesn't trust the RDS CA by default.
    # Production would bundle the RDS CA file and verify it.
    ssl_context = ssl.create_default_context()
    ssl_context.check_hostname = False
    ssl_context.verify_mode = ssl.CERT_NONE

    conn = pg8000.native.Connection(
        user=os.environ["DB_USER"],
        password=secret["password"],
        host=os.environ["DB_HOST"],
        database=os.environ["DB_NAME"],
        ssl_context=ssl_context,
    )
    conn.run("CREATE TABLE IF NOT EXISTS synced_records (id INT PRIMARY KEY, name TEXT)")

    # One S3 event can carry several uploaded files.
    for record in event["Records"]:
        bucket = record["s3"]["bucket"]["name"]
        key = unquote_plus(record["s3"]["object"]["key"])  # S3 URL-encodes keys (spaces become +)
        body = s3.get_object(Bucket=bucket, Key=key)["Body"].read().decode("utf-8")

        for row in csv.DictReader(io.StringIO(body)):
            # Upsert: re-uploading the same file doesn't create duplicates.
            conn.run(
                "INSERT INTO synced_records (id, name) VALUES (:id, :name) "
                "ON CONFLICT (id) DO UPDATE SET name = :name",
                id=int(row["id"]),
                name=row["name"],
            )

    conn.close()