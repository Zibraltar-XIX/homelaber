#!/usr/bin/env bash
#
# Déploiement du homelab en une commande :  ./setup.sh
#
# Premier lancement  : demande 3 informations, génère tous les secrets dans
#                      secrets.env, écrit la configuration, démarre le stack.
# Lancements suivants: réutilise secrets.env et remet la configuration à jour.
#
# Tout ce que ce script écrit (env/, config/, bootstrap/, .env) est jetable :
# supprime-les et relance, ils sont régénérés à l'identique depuis secrets.env.
#
set -euo pipefail
cd "$(dirname "$0")"

SECRETS_FILE=secrets.env
TINYAUTH_IMAGE=ghcr.io/tinyauthapp/tinyauth:v5

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31mERREUR:\033[0m %s\n' "$*" >&2; exit 1; }

command -v docker >/dev/null || die "docker n'est pas installé."
command -v openssl >/dev/null || die "openssl n'est pas installé."
docker compose version >/dev/null 2>&1 || die "le plugin 'docker compose' est absent."

# ══════════════════════════════════════════════════════════ 1. les secrets ══
if [ -f "$SECRETS_FILE" ]; then
  log "secrets.env trouvé — réutilisation des secrets existants."
  # shellcheck disable=SC1090
  . "./$SECRETS_FILE"
else
  log "Premier lancement. Trois informations sont nécessaires."
  read -rp "  Domaine racine (ex: homelaber.com) : " DOMAIN
  read -rp "  E-mail Let's Encrypt               : " ACME_EMAIL
  read -rp "  Token API Cloudflare (DNS:Edit)    : " CF_DNS_API_TOKEN
  [ -n "$DOMAIN" ] && [ -n "$ACME_EMAIL" ] && [ -n "$CF_DNS_API_TOKEN" ] \
    || die "les trois valeurs sont obligatoires."

  LLDAP_JWT_SECRET=$(openssl rand -hex 32)
  LLDAP_KEY_SEED=$(openssl rand -hex 32)
  LLDAP_ADMIN_PASSWORD=$(openssl rand -hex 16)
  BIND_RO_PASSWORD=$(openssl rand -hex 16)
  BREAKGLASS_PASSWORD=$(openssl rand -hex 12)

  log "Génération du hash du compte de secours…"
  docker pull -q "$TINYAUTH_IMAGE" >/dev/null
  BREAKGLASS_HASH=$(docker run --rm "$TINYAUTH_IMAGE" user create \
      --username secours --password "$BREAKGLASS_PASSWORD" --docker 2>&1 \
    | tr -d '\r' | sed -e 's/\x1b\[[0-9;]*m//g' \
    | grep -oE '\$2[aby]\$[0-9]{2}\$[A-Za-z0-9./]{53}' | head -1)
  [ -n "$BREAKGLASS_HASH" ] || die "impossible de générer le hash du compte de secours."

  umask 077
  cat > "$SECRETS_FILE" <<EOF
# Généré par setup.sh — ne jamais versionner ce fichier, mais le SAUVEGARDER.
DOMAIN='$DOMAIN'
ACME_EMAIL='$ACME_EMAIL'
CF_DNS_API_TOKEN='$CF_DNS_API_TOKEN'
LLDAP_JWT_SECRET='$LLDAP_JWT_SECRET'
LLDAP_KEY_SEED='$LLDAP_KEY_SEED'
LLDAP_ADMIN_PASSWORD='$LLDAP_ADMIN_PASSWORD'
BIND_RO_PASSWORD='$BIND_RO_PASSWORD'
BREAKGLASS_PASSWORD='$BREAKGLASS_PASSWORD'
BREAKGLASS_HASH='$BREAKGLASS_HASH'
EOF
  umask 022
  log "Secrets écrits dans $SECRETS_FILE (accès propriétaire uniquement)."
fi

# Base DN dérivée du domaine : homelaber.com -> dc=homelaber,dc=com
LDAP_BASE_DN="dc=${DOMAIN//./,dc=}"

# docker compose interpole les $ trouvés dans un env_file : un hash bcrypt
# ($2a$10$...) arriverait tronqué dans le conteneur, sans erreur. On double
# les $ pour les échapper.
BREAKGLASS_HASH_ESCAPED="${BREAKGLASS_HASH//\$/\$\$}"

# ═══════════════════════════════════════════════════ 2. la configuration ══
log "Écriture des fichiers de configuration…"
mkdir -p env config/zot bootstrap/user-configs bootstrap/group-configs \
         data/traefik data/ldap data/tinyauth data/zot/data
umask 077

# Lu par docker compose lui-même (interpolation des ${...} du compose).
cat > .env <<EOF
DOMAIN=$DOMAIN
ACME_EMAIL=$ACME_EMAIL
LLDAP_ADMIN_PASSWORD=$LLDAP_ADMIN_PASSWORD
EOF

cat > env/traefik.env <<EOF
TZ=Europe/Paris
CF_DNS_API_TOKEN=$CF_DNS_API_TOKEN
EOF

cat > env/lldap.env <<EOF
UID=1000
GID=1000
TZ=Europe/Paris
LLDAP_JWT_SECRET=$LLDAP_JWT_SECRET
LLDAP_KEY_SEED=$LLDAP_KEY_SEED
LLDAP_LDAP_USER_PASS=$LLDAP_ADMIN_PASSWORD
LLDAP_LDAP_BASE_DN=$LDAP_BASE_DN
LLDAP_HTTP_URL=https://ldap.$DOMAIN
EOF

cat > env/tinyauth.env <<EOF
TINYAUTH_APPURL=https://auth.$DOMAIN
TINYAUTH_AUTH_TRUSTEDPROXIES=172.16.0.0/12
TINYAUTH_LDAP_ADDRESS=ldap://lldap:3890
TINYAUTH_LDAP_BINDDN=uid=bind_ro,ou=people,$LDAP_BASE_DN
TINYAUTH_LDAP_BINDPASSWORD=$BIND_RO_PASSWORD
TINYAUTH_LDAP_BASEDN=$LDAP_BASE_DN
TINYAUTH_LDAP_SEARCHFILTER=(uid=%s)
TINYAUTH_LDAP_INSECURE=true
TINYAUTH_AUTH_USERS=secours:$BREAKGLASS_HASH_ESCAPED
EOF

cat > config/zot/ldap-credentials.json <<EOF
{
  "bindDN": "uid=bind_ro,ou=people,$LDAP_BASE_DN",
  "bindPassword": "$BIND_RO_PASSWORD"
}
EOF

cat > config/zot/config.json <<EOF
{
  "distSpecVersion": "1.1.1",
  "storage": {
    "rootDirectory": "/var/lib/registry",
    "gc": true, "gcDelay": "1h", "gcInterval": "6h", "dedupe": true
  },
  "http": {
    "address": "0.0.0.0",
    "port": "5000",
    "realm": "zot",
    "auth": {
      "ldap": {
        "address": "lldap",
        "port": 3890,
        "startTLS": false,
        "baseDN": "ou=people,$LDAP_BASE_DN",
        "userAttribute": "uid",
        "credentialsFile": "/etc/zot/ldap-credentials.json",
        "skipVerify": false,
        "subtreeSearch": true
      }
    },
    "accessControl": {
      "repositories": {
        "**": {
          "policies": [
            { "groups": ["registry"],
              "actions": ["read", "create", "update", "delete"] }
          ],
          "defaultPolicy": [],
          "anonymousPolicy": []
        }
      }
    }
  },
  "log": { "level": "info" }
}
EOF

# Compte de service LDAP, créé au démarrage par le conteneur lldap-bootstrap.
# lldap_strict_readonly est un groupe natif de lldap : sans lui, bind_ro se
# connecte mais ne voit que lui-même, et toute recherche d'utilisateur échoue.
cat > bootstrap/user-configs/bind_ro.json <<EOF
{
  "id": "bind_ro",
  "email": "bind_ro@$DOMAIN",
  "displayName": "LDAP bind read-only",
  "password": "$BIND_RO_PASSWORD",
  "groups": ["lldap_strict_readonly"]
}
EOF

# Groupe donnant le droit de push/pull sur le registre d'images.
cat > bootstrap/group-configs/registry.json <<'EOF'
{
  "name": "registry"
}
EOF

umask 022

# ═════════════════════════════════════════════════════════ 3. démarrage ══
log "Démarrage du stack…"
docker compose up -d --remove-orphans

log "Provisionnement LDAP (compte bind_ro, groupe registry)…"
docker compose run --rm lldap-bootstrap

log "Redémarrage des services qui dépendent du LDAP…"
docker compose up -d --force-recreate tinyauth registry

cat <<EOF

  Stack déployé.

    lldap      https://ldap.$DOMAIN        admin / $LLDAP_ADMIN_PASSWORD
    tinyauth   https://auth.$DOMAIN
    registry   https://registry.$DOMAIN

  Compte de secours tinyauth, si le LDAP tombe :
    secours / $BREAKGLASS_PASSWORD

  Ces identifiants sont relisibles à tout moment dans ./secrets.env

  Prochaine étape : crée tes utilisateurs sur https://ldap.$DOMAIN et ajoute
  au groupe "registry" ceux qui doivent utiliser le registre d'images.

EOF
