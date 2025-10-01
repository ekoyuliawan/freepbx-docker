- Abilitare fail2ban
- Rivedere volumi
- Provare DNS Cloudflare e HTTPS (Nginx reverse proxy)
### NOTES
IP=92.204.255.106
sudo iptables -I DOCKER-USER -s $IP -j DROP