# Homelaber

Stack self-hosted : reverse proxy Traefik, annuaire LDAP (lldap), SSO (tinyauth)
et registre d'images OCI privé (zot). Tout est publié en HTTPS via Cloudflare
DNS challenge.

## Licence

**Source-available, tous droits réservés** — voir [LICENSE](LICENSE).

Ce dépôt est public pour être lu, pas pour être utilisé. Aucun droit de copie,
de modification, de déploiement ni d'hébergement n'est accordé. Le choix d'une
éventuelle licence ouverte est reporté à plus tard.

Les instructions ci-dessous documentent le déploiement pour l'auteur et les
personnes qu'il autorise expressément. Pour tout autre usage, demande d'abord.

## Prérequis

- Docker Engine + plugin `docker compose`
- Un domaine géré par Cloudflare
- Un token API Cloudflare avec la permission `Zone / DNS / Edit` sur ce domaine
- Les ports 80 et 443 libres et accessibles

## Déploiement

```bash
git clone <ce-depot> homelaber
cd homelaber
./setup.sh
```

`setup.sh` demande trois informations (domaine, e-mail Let's Encrypt, token
Cloudflare), génère tous les secrets, provisionne le compte de service LDAP et
démarre le stack. Il affiche les identifiants à la fin.

Le script est idempotent : le relancer réutilise les secrets déjà présents dans
`secrets.env` et se contente de remettre la configuration à jour.

## Services

| Service  | URL                    | Rôle                                   |
|----------|------------------------|----------------------------------------|
| lldap    | `ldap.DOMAIN`          | Annuaire des utilisateurs et groupes   |
| tinyauth | `auth.DOMAIN`          | SSO / forward-auth pour Traefik        |
| registry | `registry.DOMAIN`      | Registre d'images OCI privé            |
| traefik  | —                      | Reverse proxy, certificats TLS         |

## Après le déploiement

1. Connecte-toi à `https://ldap.DOMAIN` avec `admin` et le mot de passe affiché
   par `setup.sh`.
2. Crée tes utilisateurs.
3. Ajoute au groupe `registry` ceux qui doivent pousser ou tirer des images.

```bash
docker login registry.DOMAIN
```

## Où vivent les secrets

`secrets.env` contient tous les mots de passe, et c'est le seul fichier qui
compte. Tout le reste (`.env`, `env/`, `config/`, `bootstrap/`) en est déduit
par `setup.sh` : supprime ces dossiers et relance le script, ils reviennent
identiques.

**Sauvegarde `secrets.env`.** Sans lui, il faut regénérer les mots de passe et
reprovisionner l'annuaire. Il n'est pas versionné, comme tout ce qui est généré
(voir `.gitignore`).

## Opérations courantes

```bash
docker compose ps                  # état des services
docker compose logs -f tinyauth    # logs d'un service
docker compose down                # arrêt (les données de data/ restent)
./setup.sh                         # redéploiement / mise à jour de la config
```

## Structure

Trois fichiers versionnés, c'est tout :

```
docker-compose.yml     Définition des services
setup.sh               Déploiement en une commande, et toute la configuration
README.md              Ce fichier
```

Le reste apparaît au premier `./setup.sh` et n'est jamais à modifier à la main :

```
secrets.env            Tous les secrets — le seul fichier à sauvegarder
.env env/ config/      Configuration générée depuis secrets.env
bootstrap/             Comptes et groupes LDAP provisionnés au démarrage
data/                  Données persistantes des services
```
