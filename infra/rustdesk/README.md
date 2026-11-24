# MR Remote — RustDesk Server OSS V0.1

Proposta: OCI Always Free A1 Flex (ARM64), Ubuntu 24.04 LTS, 1 OCPU, 6 GB RAM, disco 50 GB. Confirmar elegibilidade e capacidade no console antes da criação; instâncias gratuitas podem ser recuperadas por ociosidade.

## Implantação em uma VM autorizada

1. Criar VM com IPv4 público e SSH por chave, restringindo TCP 22 ao IP administrativo. Configurar regras stateful na OCI e firewall do SO: TCP 21115-21117 e UDP 21116. Bloquear 21118/21119 se não houver cliente web. Não desabilitar o firewall.
2. Instalar Docker Engine e Compose v2 (https://docs.docker.com/engine/install/ubuntu/).
3. Copiar esta pasta para /opt/mr-remote (sem dados ou credenciais). Criar `.env` a partir de `.env.example`, preenchendo o IP público ou DNS. Proteger `.env` e `data/`.
4. Executar `sudo docker compose config --quiet`, `sudo docker compose pull`, `sudo docker compose up -d hbbs`. Verificar `sudo docker compose logs hbbs` e `sudo test -s data/id_ed25519.pub`. Somente então executar `sudo docker compose up -d hbbr` para reutilizar as chaves geradas pelo hbbs.
5. Executar `sudo docker compose ps` e `sudo docker compose logs --tail=50 hbbs hbbr`. Verificar portas e conectividade externa.
6. Obter somente a chave pública: `sudo cat data/id_ed25519.pub`. Nos dois clientes de teste: ID Server = IP/DNS:21116, Relay Server = IP/DNS:21117, Key = chave pública, API Server vazio.
7. Testar acesso autorizado em duas redes distintas, consentimento, autenticação e relay. Não distribuir a clientes antes dos testes e revisão.

## Segurança

Nunca publicar `data/`, `.env`, chaves privadas, credenciais ou dados de clientes. Fazer backup criptografado da pasta data fora da VM. A chave pública do servidor não é credencial individual de técnico. A imagem está fixada na versão 1.1.16; revisar atualizações de segurança. O Compose ainda não foi executado nesta infraestrutura.

Referências: https://rustdesk.com/docs/en/self-host/rustdesk-server-oss/docker/ ; https://github.com/rustdesk/rustdesk-server/blob/master/docs/environment-variables.md ; https://docs.oracle.com/en-us/iaas/Content/FreeTier/freetier_topic-Always_Free_Resources.htm
