# Developer Sandbox Management Tool

This Bash script automates the deployment and management of developer environments (sandboxes) for the **eShopOnWeb** (.NET) and **Medplum** (Node.js/FHIR) projects. 

The script manages the entire lifecycle of the environment, from cloning repositories and patching Dockerfiles to intelligent database volume backups.

## 🚀 Key Features

* **Automated Setup**: Clones repositories (supporting specific tags like Medplum `v5.1.8`) and applies custom patches, such as upgrading to .NET 10.0 and configuring specific ports.
* **Intelligent DB Management**:
    * Automatically creates a backup of the PostgreSQL volume for Medplum during the first run.
    * Implements an **Idle Check** to ensure the database has no active transactions before archiving.
    * Restores database state from a `.tar.gz` file on subsequent starts to bypass long migration phases.
* **Dynamic IP Detection**: Automatically detects the host's local IP address to provide accurate access URLs.
* **Isolation**: Supports multi-project management using the `--project-directory` flag.

## 🛠 Usage

Run the script using the following format:
`./sandbox.sh {command} {target}`

Where **target** is: `eshop`, `medplum`, or `all`.

| Command | Description |
| :--- | :--- |
| `setup` | Clones code, patches Dockerfiles, and prepares configurations. |
| `start` | Launches containers. For Medplum, it restores the DB from backup if available. |
| `stop` | Stops containers (`down` for eShop, `stop` for Medplum). |
| `status` | Displays the status of containers for the selected project. |
| `test` | Runs tests inside the containers (`dotnet test` or `npm test`). |
| `clean` | **Full Reset**: Removes containers, images, volumes, source code, and DB backups. |

## 📦 Medplum Postgres Backup Logic

The script features advanced logic for the `medplum_medplum-postgres-data` volume:
1.  **Idle Check**: Before backing up, the script verifies `pg_stat_activity` 5 consecutive times to ensure the database is idle.
2.  **Safe Archive**: Uses a temporary `alpine` container to create a compressed archive of the volume while the stack is paused.
3.  **Fast Restore**: If `medplum_db_backup.tar.gz` is present during `start`, the script initializes the volume with this data, significantly reducing startup time.

## 📝 Requirements

* Docker and Docker Compose
* Bash
* Git
* Utilities: `awk`, `sed`, `hostname`

## 🌐 Application Access

Once started, the applications are accessible via the detected host IP:

* **eShopOnWeb**:
    * Web UI: `http://<SANDBOX_IP>:5106`
    * Swagger: `http://<SANDBOX_IP>:5200/swagger`
* **Medplum**:
    * App UI: `http://<SANDBOX_IP>:3000`
    * API Health: `http://<SANDBOX_IP>:8103/healthcheck`

---

### Development Note
All configuration changes (e.g., SDK version updates in Dockerfiles) are applied automatically during the `setup` phase. This keeps the local workspace clean and ensures customizations only exist within the sandbox environment.
