resource "helm_release" "external_dns" {
  depends_on = [module.eks, helm_release.ingress]
  name       = "external-dns"
  namespace  = local.k8s_namespace
  chart      = "external-dns"
  repository = "https://kubernetes-sigs.github.io/external-dns"
  version    = 1.20 # chart version can be added (optional)

  set {
    name  = "txtOwnerId"
    value = var.hosted_zone_id
  }
  set {
    name  = "triggerLoopOnEvent"
    value = true
  }
  set {
    name  = "policy"
    value = "sync"
  }
  set {
    name  = "domainFilters"
    value = "{${var.hosted_zone_name}}"
  }
}