FROM ubuntu:18.04
EXPOSE 22 80

RUN apt update; \
    apt install -y openssh-server

COPY ansible/roles/test-app/files/systemctl.py /usr/bin/systemctl

RUN test -L /bin/systemctl || ln -sf /usr/bin/systemctl /bin/systemctl

RUN sed -i 's/#PubkeyAuthentication/PubkeyAuthentication/' /etc/ssh/sshd_config; \
    sed -i 's/#AuthorizedKeysFile/AuthorizedKeysFile/' /etc/ssh/sshd_config; \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config; \
    service ssh start

CMD ["/usr/bin/systemctl"]
