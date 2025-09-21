### Build from source

THIS DOCKERFILE MUST BE BUILT ON DEBIAN 12 (BOOKWORM) FOR COMPATIBILITY REASONS;
OTHERWISE YOU WILL GET ERRORS DURING THE ASTERISK COMPILATION PROCESS
```bash
cd source

tar xvf asterisk-21-current.tar.gz 
tar zxvf freepbx-17.0-latest-EDGE.tgz

docker build -t freepbx:custom .

docker exec <ctr> sh -lc 'printf "ServerName pbx.example.com\n" >/etc/apache2/conf-available/servername.conf && a2enconf servername && apache2ctl -k graceful'

docker run -e SERVER_NAME=pbx.example.com
```

Breve: no, non è necessario “gestirla” nel Dockerfile per farla funzionare. L’entrypoint che legge SERVER_NAME a runtime è la soluzione giusta. Nel Dockerfile puoi solo impostare un default, se vuoi.

Cosa fare nel Dockerfile

Opzionale (default documentato): aggiungi una riga ENV SERVER_NAME=localhost. Questo crea un valore predefinito, ma può essere sovrascritto a runtime.
Evita di scrivere il ServerName in build: rimuovi/evita RUN echo "ServerName localhost" >> /etc/apache2/apache2.conf (vedi source/Dockerfile:54). Ci pensa l’entrypoint.
Come passarla a runtime

Docker run: docker run -e SERVER_NAME=pbx.example.com …
Docker Compose:
environment:
SERVER_NAME=pbx.example.com