locals {
  k8s_namespace = var.existing_namespace ? var.custom_namespace : "dbt-cloud-${var.namespace}-${var.environment}"
}


resource "kubernetes_service_account" "efs_provisioner" {
  count = var.create_efs_provisioner ? 1 : 0
  metadata {
    name      = "efs-provisioner"
    namespace = local.k8s_namespace
  }

  automount_service_account_token = true
}

resource "kubernetes_cluster_role" "efs_provisioner_runner" {
  count = var.create_efs_provisioner ? 1 : 0
  metadata {
    name = "efs-provisioner-runner"
  }

  rule {
    api_groups = [""]
    resources  = ["persistentvolumes"]
    verbs      = ["get", "list", "watch", "create", "delete"]
  }

  rule {
    api_groups = [""]
    resources  = ["persistentvolumeclaims"]
    verbs      = ["get", "list", "watch", "update"]
  }

  rule {
    api_groups = ["storage.k8s.io"]
    resources  = ["storageclasses"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = [""]
    resources  = ["events"]
    verbs      = ["create", "update", "patch"]
  }

  rule {
    api_groups = [""]
    resources  = ["endpoints"]
    verbs      = ["get", "list", "watch", "create", "update", "patch"]
  }
}

resource "kubernetes_cluster_role_binding" "run_efs_provisioner" {
  count = var.create_efs_provisioner ? 1 : 0
  metadata {
    name = "run-efs-provisioner"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "efs-provisioner-runner"
  }
  subject {
    kind      = "ServiceAccount"
    name      = "efs-provisioner"
    namespace = local.k8s_namespace
  }
}

resource "kubernetes_role" "leader_locking_efs_provisioner" {
  count = var.create_efs_provisioner ? 1 : 0
  metadata {
    name      = "leader-locking-efs-provisioner"
    namespace = local.k8s_namespace
  }
  rule {
    api_groups = [""]
    resources  = ["endpoints"]
    verbs      = ["get", "list", "watch", "create", "update", "patch"]
  }
}

resource "kubernetes_role_binding" "leader_locking_efs_provisioner" {
  count = var.create_efs_provisioner ? 1 : 0
  metadata {
    name      = "leader-locking-efs-provisioner"
    namespace = local.k8s_namespace
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = "leader-locking-efs-provisioner"
  }
  subject {
    kind      = "ServiceAccount"
    name      = "efs-provisioner"
    namespace = local.k8s_namespace
  }
  subject {
    kind      = "Group"
    name      = "system:masters"
    api_group = "rbac.authorization.k8s.io"
  }
}

resource "kubernetes_config_map" "efs_provisioner" {
  count = var.create_efs_provisioner ? 1 : 0
  metadata {
    name      = "efs-provisioner"
    namespace = local.k8s_namespace
  }

  data = {
    "file.system.id"   = module.efs.id
    "aws.region"       = var.region
    "provisioner.name" = "example.com/aws-efs"
    "dns.name"         = ""
  }
}

resource "kubernetes_deployment" "efs_provisioner" {
  count = var.create_efs_provisioner ? 1 : 0
  metadata {
    name      = "efs-provisioner"
    namespace = local.k8s_namespace
    labels = {
      name = "efs-provisioner"
    }
  }

  spec {
    replicas = 1

    strategy {
      type = "Recreate"
    }

    selector {
      match_labels = {
        app = "efs-provisioner"
      }
    }

    template {
      metadata {
        labels = {
          app = "efs-provisioner"
        }
      }

      spec {
        service_account_name            = "efs-provisioner"
        automount_service_account_token = true

        container {
          name  = "efs-provisioner"
          image = "quay.io/external_storage/efs-provisioner:latest"

          env {
            name = "FILE_SYSTEM_ID"
            value_from {
              config_map_key_ref {
                name = "efs-provisioner"
                key  = "file.system.id"
              }
            }
          }
          env {
            name = "AWS_REGION"
            value_from {
              config_map_key_ref {
                name = "efs-provisioner"
                key  = "aws.region"
              }
            }
          }
          env {
            name = "DNS_NAME"
            value_from {
              config_map_key_ref {
                name = "efs-provisioner"
                key  = "dns.name"
              }
            }
          }
          env {
            name = "PROVISIONER_NAME"
            value_from {
              config_map_key_ref {
                name = "efs-provisioner"
                key  = "provisioner.name"
              }
            }
          }

          volume_mount {
            name       = "pv-volume"
            mount_path = "/persistentvolumes"
          }

        }

        volume {
          name = "pv-volume"
          nfs {
            server = module.efs.dns_name
            path   = "/"
          }
        }
      }
    }
  }
}

resource "kubernetes_storage_class" "aws_efs" {
  count = var.create_efs_provisioner ? 1 : 0
  metadata {
    name = "aws-efs"
  }
  storage_provisioner = "example.com/aws-efs"
}

resource "kubernetes_persistent_volume_claim" "efs" {
  count = var.create_efs_provisioner ? 1 : 0
  metadata {
    name = "efs"
    annotations = {
      "volume.beta.kubernetes.io/storage-class" = kubernetes_storage_class.aws_efs.0.metadata.0.name
    }
    namespace = local.k8s_namespace
  }
  spec {
    access_modes = ["ReadWriteMany"]
    resources {
      requests = {
        storage = "1Mi"
      }
    }
  }
}
