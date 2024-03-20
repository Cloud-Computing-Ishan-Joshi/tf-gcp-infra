#!/bin/bash

# Ensure the directory exists
mkdir -p /usr/env_webapp

# Create or overwrite the .env file
cat <<EOF > /usr/env_webapp/.env
DB_HOST=${db_host}
DB_USER=${db_user}
DB_PASSWORD=${db_password}
DB_NAME=${db_name}
NODE_ENV=dev
EOF

# Set permissions
chmod 655 /usr/env_webapp/.env
chown ${chown_user}:${chown_user} /usr/env_webapp/.env

# Run the application service
sudo systemctl start webapp