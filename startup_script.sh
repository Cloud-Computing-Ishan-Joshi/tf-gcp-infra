#!/bin/bash

# Ensure the directory exists
mkdir -p /var/env_webapp

# Create or overwrite the .env file
cat <<EOF > /var/env_webapp/.env
DB_HOST=${db_host}
DB_USER=${db_user}
DB_PASSWORD=${db_password}
DB_NAME=${db_name}
NODE_ENV=test
EOF

# Set permissions
chmod 655 /var/env_webapp/.env
chown ${chown_user}:${chown_user} /var/env_webapp/.env
