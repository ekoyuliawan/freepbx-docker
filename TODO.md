- Provare a installare freepbx senza supporto DAHDI rimuovendo il package "linux-headers-`uname -r`"
- Abilitare fail2ban
- Provare start e stop del progetto compose per vedere se il comando
sudo docker compose exec -it -w /usr/local/src/freepbx freepbx php install -n --dbuser=freepbxuser --dbpass="$(cat freepbxuser_password.txt)" --dbhost=db
ci vuole ogni volta o meno
- Rivedere volumi
- Abilitare Git LFS per salvare o le cartelle sorgenti di asterisk/freepbx oppure gli archivi al posto delle cartelle (una delle due opzioni)
- Provare DNS Cloudflare e HTTPS (Nginx reverse proxy)
- Sistemare /etc/resolv.conf DNS interno Docker
- Provare registrazione SIP

pbx-ec2.pstn.twilio.com (Termination SIP URI)
pbx-ec2 (friendly name)
559jbJbFJy!pbx (username)
8yYpX5&Ytra3H&RS9@o%oF (password)