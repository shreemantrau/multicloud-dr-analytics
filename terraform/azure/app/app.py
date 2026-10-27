from flask import Flask                                # Flask is the web framework: it turns Python functions into HTTP routes
import os                                              # Reads settings from environment variables
import pymssql                                         # SQL Server driver; pure Python, so the container needs no extra system packages
from azure.identity import DefaultAzureCredential      # Finds the app's Managed Identity automatically (no password in code)
from azure.keyvault.secrets import SecretClient        # Client for reading secrets from Key Vault


app = Flask(__name__)            # Creates the app object; __name__ tells Flask where to find this file

@app.route("/health")            # Maps the URL /health to the function below
def health():
    return "OK", 200             # Body "OK" with HTTP status 200; used to check the app is alive

@app.route("/db")
def db_check():
    # 1. Settings come from environment variables, set in Terraform (app_settings), so the code has no hardcoded names
    vault_name = os.environ["KEY_VAULT_NAME"]          # kv-proj3-dr-analytics
    sql_server = os.environ["SQL_SERVER"]              # sql-proj3-dr-analytics.database.windows.net
    sql_db     = os.environ["SQL_DB"]                  # proj3-dr-analytics
    sql_user   = os.environ["SQL_USER"]                # sqladmin

    # 2. Authenticate to Key Vault as the app's Managed Identity and read the SQL password
    #    Goes through the private endpoint because vnet_route_all_enabled sends DNS and traffic via the VNet
    client = SecretClient(
        vault_url=f"https://{vault_name}.vault.azure.net",
        credential=DefaultAzureCredential(),
    )
    sql_password = client.get_secret("sql-password").value   # Needs the Key Vault Secrets User role

    # 3. Connect to SQL through its private endpoint (port 1433, allowed from the app subnet by the NSG)
    conn = pymssql.connect(server=sql_server, user=sql_user, password=sql_password, database=sql_db)
    cursor = conn.cursor()
    cursor.execute("SELECT 1")                         # Simplest possible query: proves the whole path works
    result = cursor.fetchone()[0]
    conn.close()                                       # Always close the connection when done

    return {"db_result": result}, 200                  # Flask turns the dict into JSON

if __name__ == "__main__":       # Runs only when the file is started directly (not when imported); must stay the LAST block
    app.run(host="0.0.0.0", port=5000)   # 0.0.0.0 = listen on all interfaces, so the container is reachable; 5000 matches the NSG rule