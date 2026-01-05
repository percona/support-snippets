# Docker Setup Scripts

This directory contains scripts to setup MongoDB containers with various configurations.

## Usage Notes

- **Topology assumption:** Scripts that don't have `_rs` or `_sharded` in their name should be assumed to work with replica sets (`_rs`).
- **Command blocks:** Commands that are not followed by double blank lines can be executed together as a single block. Double blank lines indicate the end of a logical block of commands or a pause point or where you should wait for the previous commands to complete before continuing.
- The `Base Setup` scrips are always necessary. For any setup that involves TLS, the `docker_setup_tls_base_certs.sh` is necessary too.

## Scripts

### Base Setup

| Script | Description |
|--------|-------------|
| `docker_setup_psmdb_rs.bash` | Local PSMDB docker replica set |
| `docker_setup_psmdb_sharded.bash` | Local PSMDB docker sharded cluster |
| `docker_setup_psmdb_single.bash` | Local PSMDB docker multiple standalone instances |

### TLS/SSL Configuration

| Script | Description |
|--------|-------------|
| `docker_setup_tls_base_certs.sh` | Base script that creates the CA and the signed certificates for MongoDB and clients |
| `docker_setup_tls_scram_client.bash` | x509 certificates for internal authentication, clients use SCRAM-SHA-256 |
| `docker_setup_tls_x509_client.bash` | x509 certificates for internal and external authentication |

### LDAP Configuration

NativeLDAP authentication and authorization for a replica set.

| Script | Description |
|--------|-------------|
| `docker_setup_ldap.bash` | Simple bind, TLS disabled |
| `docker_setup_ldap_tls.bash` | Simple bind, TLS enabled between MongoDB and LDAP, not for clients |
| `docker_setup_ldap_x509_client.bash` | Simple bind, TLS enabled among all entities, clients authenticating with x509 certificates |
| `docker_setup_ldap_bind_digestmd5.bash` | External bind via client's PLAIN credentials. TLS disabled |
| `docker_setup_ldap_bind_external.bash` | External bind via client's x509 certificates, TLS enabled among all entities |

### SASL Configuration

| Script | Description |
|--------|-------------|
| `docker_setup_sasl_rs.bash` | Configures SASL authentication for a replica set |
| `docker_setup_sasl_sharded.bash` | Configures SASL authentication for a sharded cluster. All the MongoDB part is done on mongos |

### Encryption at Rest

| Script | Description |
|--------|-------------|
| `docker_setup_kmip.bash` | Configures KMIP server for data-at-rest encryption for a replica set. TLS enabled between MongoDB and KMIP |

### PMM (Percona Monitoring and Management)

| Script | Description |
|--------|-------------|
| `docker_setup_pmm2_server.bash` | Docker PMM 2.x server setup |
| `docker_setup_pmm2_client_rs.bash` | Docker PMM 2.x client setup |
| `docker_setup_pmm3_server.bash` | Docker PMM 3.x server setup |
| `docker_setup_pmm3_client_rs.bash` | Docker PMM 3.x client setup |

### MongoDB Exporter

| Script | Description |
|--------|-------------|
| `docker_setup_psmdb_exporter_rs.bash` | mongodb-exporter setup to run with docker replica set |
| `docker_setup_psmdb_exporter_sharded.bash` | mongodb-exporter setup to run with docker sharded cluster |

### Backup (PBM)

| Script | Description |
|--------|-------------|
| `docker_setup_psmdb_pbm.bash` | PBM setup to run with docker replica set |
| `docker_setup_minio.bash` | Minio setup to run with PBM docker setup |
