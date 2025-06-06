# ---------------------------------------------------------------------------- #
# Local Variables
# ---------------------------------------------------------------------------- #

locals {
  tunnel_dns = [
    {
      protocol = "http"
      name     = "@" #! root
      host     = "10.0.40.20"
      hostname = var.cf_domain
      port     = 11111
    },
    # {
    #   protocol = "http"
    #   name     = "atlantis"
    #   host     = "10.0.40.21"
    #   hostname = "atlantis.${var.cf_domain}"
    #   port     = 4141
    # },
    {
      protocol = "http"
      name     = "grafana"
      host     = "10.0.40.20"
      hostname = "grafana.${var.cf_domain}"
      port     = 3000
    },
    {
      protocol = "http"
      name     = "hass"
      host     = "10.0.40.21"
      hostname = "hass.${var.cf_domain}"
      port     = 8123
    },
    {
      protocol = "http"
      name     = "jellyfin"
      host     = "10.0.40.20"
      hostname = "jellyfin.${var.cf_domain}"
      port     = 8096
    },
    {
      protocol = "http"
      name     = "jenkins"
      host     = "10.0.40.22"
      hostname = "jenkins.${var.cf_domain}"
      port     = 8080
    },
    {
      protocol = "http"
      name     = "n8n"
      host     = "10.0.40.21"
      hostname = "n8n.${var.cf_domain}"
      port     = 5678
    },
    {
      protocol = "http"
      name     = "overseerr"
      host     = "10.0.40.20"
      hostname = "overseerr.${var.cf_domain}"
      port     = 5055
    },
    {
      protocol = "http"
      name     = "plex"
      host     = "10.0.40.2"
      hostname = "plex.${var.cf_domain}"
      port     = 32400
    },
    {
      protocol = "http"
      name     = "prometheus"
      host     = "10.0.40.20"
      hostname = "prometheus.${var.cf_domain}"
      port     = 9090
    },
    {
      protocol = "http"
      name     = "prowlarr"
      host     = "10.0.40.20"
      hostname = "prowlarr.${var.cf_domain}"
      port     = 9696
    },
    {
      protocol = "http"
      name     = "radarr"
      host     = "10.0.40.20"
      hostname = "radarr.${var.cf_domain}"
      port     = 7878
    },
    {
      protocol = "http"
      name     = "sabnzbd"
      host     = "10.0.40.20"
      hostname = "sabnzbd.${var.cf_domain}"
      port     = 18080
    },
    {
      protocol = "http"
      name     = "sonarr"
      host     = "10.0.40.20"
      hostname = "sonarr.${var.cf_domain}"
      port     = 8989
    },
  ]

  other_dns = [
    {
      name    = "external"
      proxied = true
      content = "${cloudflare_zero_trust_tunnel_cloudflared.tunnel.id}.cfargotunnel.com"
      type    = "CNAME"
      ttl     = 1
    },
  ]
}

# ---------------------------------------------------------------------------- #
# Tunnel Configuration
# ---------------------------------------------------------------------------- #

resource "random_password" "tunnel_secret" {
  length  = 32
  special = false
  upper   = true
  lower   = true
  numeric = true
}

resource "cloudflare_zero_trust_tunnel_cloudflared" "tunnel" {
  account_id    = var.cf_account_id
  name          = var.tunnel_name
  tunnel_secret = random_password.tunnel_secret.result
}

resource "hcp_vault_secrets_secret" "tunnel_credential" {
  app_name    = var.hcp_secret_app_name
  secret_name = replace("${var.tunnel_name}_credential", "-", "_")
  secret_value = jsonencode({
    AccountTag   = var.cf_account_id
    TunnelID     = cloudflare_zero_trust_tunnel_cloudflared.tunnel.id
    TunnelName   = cloudflare_zero_trust_tunnel_cloudflared.tunnel.name
    TunnelSecret = random_password.tunnel_secret.result
  })
}

# ---------------------------------------------------------------------------- #
# DNS Records
# ---------------------------------------------------------------------------- #

resource "cloudflare_dns_record" "tunnel_dns_records" {
  for_each = { for domain in local.tunnel_dns : domain.name => domain }
  zone_id  = var.cf_zone_id
  name     = each.value.name
  content  = "${cloudflare_zero_trust_tunnel_cloudflared.tunnel.id}.cfargotunnel.com"
  type     = "CNAME"
  proxied  = true
  ttl      = 1
  comment  = "Managed by Terraform"
}

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "tunnel_config" {
  account_id = var.cf_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.tunnel.id

  config = {
    ingress = concat(
      [
        for domain in local.tunnel_dns : {
          hostname = domain.hostname
          service  = "${domain.protocol}://${domain.host}:${domain.port}"
        }
      ],
      [
        {
          service = "http_status:404"
        }
      ]
    )
  }
}

resource "cloudflare_dns_record" "dns_records" {
  for_each = { for domain in local.other_dns : domain.name => domain }
  zone_id  = var.cf_zone_id
  name     = each.value.name
  content  = each.value.content
  type     = each.value.type
  proxied  = each.value.proxied
  ttl      = each.value.ttl
  comment  = "Managed by Terraform"
}

# ---------------------------------------------------------------------------- #
# Zero Trust Access Configurations
# ---------------------------------------------------------------------------- #

resource "cloudflare_zero_trust_access_policy" "example_zero_trust_access_policy" {
  account_id       = var.cf_account_id
  decision         = "bypass"
  include          = [{ everyone = {} }]
  name             = "Application Bypass TF"
  session_duration = "30m"
}

resource "cloudflare_zero_trust_access_application" "atlantis" {
  zone_id           = var.cf_zone_id
  name              = "Atlantis"
  domain            = "atlantis.${var.cf_domain}"
  type              = "self_hosted"
  session_duration  = "24h"
  skip_interstitial = true

  depends_on = [
    cloudflare_zero_trust_access_policy.example_zero_trust_access_policy
  ]
}

resource "cloudflare_zero_trust_access_application" "hass" {
  zone_id           = var.cf_zone_id
  name              = "Home Assistant"
  domain            = "hass.${var.cf_domain}"
  type              = "self_hosted"
  session_duration  = "24h"
  skip_interstitial = true

  depends_on = [
    cloudflare_zero_trust_access_policy.example_zero_trust_access_policy
  ]
}

# resource "cloudflare_zero_trust_access_application" "jellyfin" {
#   zone_id           = var.cf_zone_id
#   name              = "Jellyfin"
#   domain            = "jellyfin.${var.cf_domain}"
#   type              = "self_hosted"
#   session_duration  = "24h"
#   skip_interstitial = true

#   depends_on = [
#     cloudflare_zero_trust_access_policy.example_zero_trust_access_policy
#   ]
# }
