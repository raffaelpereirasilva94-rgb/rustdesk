# MR Remote — RustDesk Server OSS V0.1

## Ambiente de laboratório validado em 24/11/2026
AWS EC2, São Paulo (sa-east-1), t3.micro (x86_64, 1 GiB RAM), Ubuntu 24.04 LTS, Docker Compose v2 e RustDesk Server OSS 1.1.16. Plano gratuito temporário por créditos, não hospedagem permanente. Monitorar saldo, prazo e tráfego. O IP público automático pode mudar após stop/start; planejar DNS ou IP estável antes de distribuição.

## Implantação em uma VM autorizada

1. Criar VM com IPv4 público e SSH por chave, restringindo TCP 22 ao IPv4 administrativo /32. Configurar Security Group e firewall do SO: TCP 21115-21117 e UDP 21116. Restringir aos IPs de teste quando viável; não liberar 21118/21119 para clientes desktop. Não desabilitar o firewall.
2. Instalar Docker Engine e Compose v2 (https://docs.docker.com/engine/install/ubuntu/).
3. Copiar esta pasta para /opt/mr-remote (sem dados ou credenciais). Criar `.env` a partir de `.env.example`, preenchendo IP público ou DNS. Proteger `.env` (0600) e `data/` (0700).
4. Executar `sudo docker compose config --quiet`, `sudo docker compose pull`, `sudo docker compose up -d hbbs`. Verificar `sudo docker compose logs hbbs` e `sudo test -s data/id_ed25519.pub`. Somente então executar `sudo docker compose up -d hbbr` para reutilizar as chaves geradas pelo hbbs.
5. Executar `sudo docker compose ps` e `sudo docker compose logs --tail=50 hbbs hbbr`. Verificar portas e conectividade externa. Verificar UDP com captura restrita à porta 21116, sem publicar dados de clientes.
6. Obter somente a chave pública: `sudo cat data/id_ed25519.pub; echo`. Nos dois clientes: ID Server = IP/DNS; Relay Server vazio (anunciado pelo HBBS); Key = chave pública; API Server vazio.
7. Testar acesso autorizado em duas redes distintas, consentimento, autenticação, Relay forçado e encerramento. Desativar Relay forçado após o teste.

## Segurança e continuidade

Nunca publicar `data/`, `.env`, chaves privadas, credenciais ou dados de clientes. Manter backup criptografado das chaves fora da VM, verificar integridade e descriptografia; planejar também backup completo dos dados e restauração em laboratório. Não regenerar chaves durante atualizações. A chave pública do servidor não é credencial individual de técnico. A imagem está fixada por tag 1.1.16, não por digest; revisar atualizações de segurança e pinagem antes de produção. O uso de host network exige regras de firewall na VM/nuvem. O responsável confirmou a operação dos dois serviços, TCP/UDP, Relay, persistência e backup de chaves. Não foi realizada auditoria independente.

Referências: https://rustdesk.com/docs/en/self-host/rustdesk-server-oss/docker/ ; https://github.com/rustdesk/rustdesk-server ; https://aws.amazon.com/free/
