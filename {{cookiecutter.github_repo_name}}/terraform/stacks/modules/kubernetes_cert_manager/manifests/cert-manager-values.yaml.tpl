affinity:
  nodeAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
    - weight: 1
      preference:
        matchExpressions:
        - key: node-group
          operator: In
          values:
          - {{ cookiecutter.global_platform_shared_resource_identifier }}
serviceAccount:
  annotations:
    eks.amazonaws.com/role-arn: ${role_arn}
  name: cert-manager
  namespace: ${namespace}
# the securityContext is required, so the pod can access files required to assume the IAM role
securityContext:
  # -------------------------------------------------------------------------------
  # mcdaniel dec-2022: see https://github.com/cert-manager/cert-manager/issues/5549
  #enabled: true
  # -------------------------------------------------------------------------------
  fsGroup: 1001
