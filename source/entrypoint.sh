#!/usr/bin/env bash
set -e

# Start cron
/usr/sbin/cron &

# Start postfix email service
service postfix start

# Start Asterisk service
/usr/local/src/freepbx/start_asterisk start &

# Start Fail2ban
fail2ban-client start &

exec apache2ctl -D FOREGROUND
