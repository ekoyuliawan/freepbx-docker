# Configure Apache ServerName from env (default: localhost)
SERVER_NAME_VALUE="${SERVER_NAME:-localhost}"
printf "ServerName %s\n" "$SERVER_NAME_VALUE" > /etc/apache2/conf-available/servername.conf
# Enable the conf idempotently and validate syntax
a2enconf servername >/dev/null 2>&1 || true
apache2ctl -t || echo "[WARN] Apache config validation failed"

# Start Asterisk service
/usr/src/freepbx/start_asterisk start &

# Start Fail2ban
fail2ban-client start &

apache2ctl -D FOREGROUND
