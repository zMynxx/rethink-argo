<p><a target="_blank" href="https://app.eraser.io/workspace/F95eLPbElWDqPYpdYBwV" id="edit-in-eraser-github-link"><img alt="Edit in Eraser" src="https://firebasestorage.googleapis.com/v0/b/second-petal-295822.appspot.com/o/images%2Fgithub%2FOpen%20in%20Eraser.svg?alt=media&amp;token=968381c8-a7e7-472a-8ed6-4a6626da5501"></a></p>

![image.png](/.eraser/F95eLPbElWDqPYpdYBwV___TQmgywa6AXge7WJMnlClJmSiIXA2___QhWnNXCJ2CqqEgMSGqx1c.png "image.png")

# What is [Argo]([﻿argoproj.github.io/](https://argoproj.github.io/))?
Open source tools for Kubernetes to run workflows, manage clusters, and do GitOps right.

As of today, most significant tooling by Argo are:

- CD (with Notifications out-of-the-box)
- Events
- Workflows
- Rollouts
## What's the plan?
We are going to start by talk about basic and advanced ArgoCD features:

- ApplicationSet - What is it and how to use it ?
- Notifications 101
- Sync waves for the typical project
- Multi-Cluster management best practices
- Webhooks, polling - why and why not ?
- Different Sync options
Then we will try our Argo Rollouts and Argo Workflows, and examine the use cases, benefits.

## The Goal
**<PASTE IMAGE HERE>**

By the end of this session we should be capable of managing multiple Kubernetes cluster using a single Git repository, and a single ArgoCD deployment. All declaratively configured, leveraging different ArgoCD capabilities.

### Prerequisites 
- Kubernetes clusters, we'll refer to 1 of them as "mgmt" (=management).
- ArgoCD deployed into the management cluster.
- Kustomize.
### Step to reproduce:
1. Create a **private** git repository, we'll be using GitHub.
2. Integrate with ArgoCD (Webhook or Polling).
3. Configure projects, policies, and clusters decleratively.
4. Create an Application manifest (using ApplicationSet or AppOfApps pattern).
5. Create Kustomize overlay for the different environments to match the manifests.
6. Create an application to be deployed in a later sync wave.
7. Set up notification via slack channel.


## GitHub Integration: Webhook vs. Polling
By design, ArgoCD uses polling to sync the desired state with the actual state. However, something we might want / need to use webhook.

Let's compare the two:

|  | Polling | Webhook |
| ----- | ----- | ----- |
| Requires public ArgoCD endpoint | x | v |
| Automatically triggers sync | v | x |
| Diff up to 3 minutes | v | x |
| Easy to setup | v | v |
#### [Webhook setup]([﻿argo-cd.readthedocs.io/en/stable/operator-manual/webhook/#git-webhook-configuration](https://argo-cd.readthedocs.io/en/stable/operator-manual/webhook/#git-webhook-configuration)):
In order for the webhook to work as expected, a few thing must be in order. Firstly, our ArgoCD endpoint must be available for GitHub, so it could invoke it from outside our environment. Then, under repository `Settings > Webhooks > Add Webhook` set the following:

```
Endpoint: www.rethink-argocd.develeap.com/api/webhook
Content-type: application/json 
Secret: my-super-secret
```
And set the trigger according to your needs.

Then, edit / patch the kubernetes secret `argocd-secret` (which reside the same namespace as our argocd server, `namespace: argocd`  by default) manifest to contain the same webhook secret, and apply. Then same pattern of using secret available to argocd repeats itself in this lesson.

```
apiVersion: v1
kind: Secret
metadata:
  name: argocd-secret
  namespace: argocd
type: Opaque
data:
...

stringData:
  # github webhook secret
  webhook.github.secret: my-super-secret
```
_*Patch operations are easier with Kustomize._

_**Kustomize can also be integrated with SOPS._

### Configure the repository
Althought we have configured the webhook which seems like all the integration between GitHub and ArgoCD, it is infact only the configuration allowing to github reach out to argo and say "Hey argo! Start sync, please".

Setting a repository is quite simple, we'll stick to the SSH method. Again, notice the unique annotation!

```
apiVersion: v1
kind: Secret
metadata:
  name: my-private-ssh-repo
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repository
stringData:
  project: *
  url: ssh://git@github.com/develeap/rethink-argo.git
  sshPrivateKey: |
    -----BEGIN OPENSSH PRIVATE KEY-----
    ...
    -----END OPENSSH PRIVATE KEY-----
  insecure: "true" # Do not perform a host key check for the server. Defaults to "false"
  enableLfs: "true" # Enable git-lfs for this repository. Defaults to "false"
```
### Configure Projects, Policies and Clusters
For the sake of readability, ease of search, debug, use and operate, and also to fully match the desired state describe in the Goal image, we will separate each and every cluster with it's own project and policies. For the sake of learning, we will focus and/or create resource for the dev and prod only. However do make sure to implement the same methodology across all environments.

##### Clusters
Let's set up the clusters first, we will create a secret for each of our cluster endpoints, notice the unique annotation, which is required by argocd.

```
kind: Secret
data:
  # Within Kubernetes these fields are actually encoded in Base64; they are decoded here for convenience.
  # (They are likewise decoded when passed as parameters by the Cluster generator)
  config:|
    {
      "bearerToken": "<authentication token>",
      "tlsClientConfig": {
        "insecure": false,
        "caData": "<base64 encoded certificate>"
      }
    }
  name: "dev"
  server: "https://dev.rethink-argo.develeap.com:6443"
  project: "dev"
metadata:
  labels:
    argocd.argoproj.io/secret-type: cluster
# (...)
```
*Again, Kustomize can make our life easier by using secretGenerators.

##### Project and Policies
Creating a project declaratively requires an `AppProject` manifest, and for each project we would have to declare and assign the permissions policies.

```
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: development
  namespace: argocd
  # Finalizer that ensures that project is not deleted until it is not referenced by any application
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  roles:
    # A role which provides read-only access to all applications in the project
    - name: production-devops
      description: devops privileges to production project
      policies:
        ## Structure: p, <role/user/group>, <resource>, <action>, <appproject>/<object>
        # DevOps can do anything
        - p, proj:development:devops, *, *, dev/*, allow
        
        # Developers can manage applicationsets, application, exec into pods and view logs
        - p, proj:development:developer, applicationsets, get, dev/*, allow
        - p, proj:development:developer, applicationsets, create, dev/*, allow
        - p, proj:development:developer, applicationsets, delete, dev/*, allow
        - p, proj:development:developer, applicationsets, update, dev/*, allow
        - p, proj:development:developer, applications, get, dev/*, allow
        - p, proj:development:developer, applications, create, dev/*, allow
        - p, proj:development:developer, applications, delete, dev/*, allow
        - p, proj:development:developer, applications, update, dev/*, allow
        - p, proj:development:developer, applications, override, dev/*, allow
        - p, proj:development:developer, applications, sync, dev/*, allow
        - p, proj:development:developer, logs, get, dev/*, allow
        - p, proj:development:developer, exec, create, dev/*, allow

      groups: #OIDC or Kubernetes RBAC Groups 
        - devops
        - developers

  # Project description
  description: development environment

  # Allow manifests to deploy from out GitOps repos.
  sourceRepos:
    - https://github.com/develeap/rethink-argo.git

  destinations:
    ## Allow all access
    - namespace: *
      server: https://dev.rethink-argo.develeap.com:6443
      name: dev

  clusterResourceWhitelist:
    - group: *
      kind: *

  namespaceResourceWhitelist:
    - group: *
      kind: *

  # Enables namespace orphaned resource monitoring.
  orphanedResources:
    warn: false
```
# RBAC - ! Keep In Mind !
RBAC permissions in argocd divides into 2 sections:

- All resources _except_ application-specific permissions (see next bullet):
`p, <role/user/group>, <resource>, <action>, <object>` 

- Applications, applicationsets, logs, and exec (which belong to an `AppProject` ):
`p, <role/user/group>, <resource>, <action>, <appproject>/<object>` 



### Edit the ConfigMap
```
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-rbac-cm
  namespace: argocd
data:
  scopes: '[groups]' # include 'emails' if using OIDC
  policy.default: role:none
  policy.csv: |-
    # Access Control
    p, role:none, applications, get, */*, deny
    p, role:none, certificates, get, *, deny
    p, role:none, clusters, get, *, deny
    p, role:none, repositories, get, *, deny
    p, role:none, projects, get, *, deny
    p, role:none, accounts, get, *, deny
    p, role:none, gpgkeys, get, *, deny
  
    # Give developers access to the different environments
    p, proj:development:developer, clusters, get, https://dev.rethink-argo.develeap.com:6443, allow
    p, proj:development:developer, repositories, get, https://github.com/develeap/rethink-argo.git, allow
    p, proj:development:developer, projects, get, development, allow
    g, develeap:developers, proj:development:developer
    
    # .... Ommitted .. #
    
    p, proj:production:developer, clusters, get, https://prod.rethink-argo.develeap.com:6443, allow
    p, proj:production:developer, repositories, get, https://github.com/develeap/rethink-argo.git, allow
    p, proj:production:developer, projects, get, production, allow
    g, develeap:developers, proj:production:developer
    
    
    # Give devops the ability to administer
    p, role:devops, clusters, *, *, allow
    p, role:devops, repositories, get, https://github.com/develeap/rethink-argo.git, allow
    p, role:devops, projects, *, *, allow
    g, develeap:devops, role:devops
```
#### Creating Applications, using a tamplate
One of the resources ArgoCD lets us leverage is called ApplicationSet.

This resource allow us to use templating to generate multiple Applications, following the same standards. Let's take a look:

```
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: applicationset
  namespace: argocd
spec:
  # Use go for this templating
  #could also be 'fasttemplate', which is soon to be deprecated.
  goTemplate: true
  goTemplateOptions: ["missingkey=error"]
  generators:
    # Traverse the given repository’s HEAD branch (latest main)
    # and for every folder under 'charts'
    # create an Application, using the template spec
    - git:
        repoURL: https://github.com/develeap/rethink-argo.git
        revision: HEAD
        directories:
          - path: charts/*
            # We can also exclude specific application who's standard does no match
            # exclude: charts/external-secrets
  template:
    metadata:
      # use folder name as the application's name
      # for example, nginx
      name: "{{path.basename}}"
      
      # Application must be deployed into the same namespace as our argocd server
      # for argo to manage and visualize in the dashboard
      namespace: argocd
      finalizers:
        - resources-finalizer.argocd.argoproj.io
    spec:
      # Deploy into specific projects, allows segregation.
      project: default
      syncPolicy:
        syncOptions:
          - CreateNamespace=true
        automated:
          prune: true
          selfHeal: false
          allowEmpty: false
      source:
        repoURL: https://github.com/smipin/gitops.git
        targetRevision: HEAD
        
        # The generator above creates a list, where each item is a path within the repository
        # for example, https://github.com/smipin/gitops/charts/nginx
        path: "{{path}}"
        helm:
          # Helm values files for overriding values in the helm chart
          # The path is relative to the spec.source.path directory defined above
          valueFiles:
            - values.yaml
      destination:
        # Deploy to specific servers
        server: https://kubernetes.default.svc
        
        # use folder name as the application's namespace
        # also matches the application name.
        namespace: "{{path.basename}}"
```
Now that we understand what is an ApplicationSet, it's abilities, structure and so forth, let's apply our knowledge to match our desired architecture.

This time, the major difference will be at the generator, we will use `matrix`  to mix and match both clusters and applications.

we are going to match each Kustomize overlay to the matching cluster, in the match project.

```
generators:
# matrix 'parent' generator
- matrix:
    generators:
      # git generator, 'child' #1
      - git:
          repoURL: ssh://git@github.com/develeap/rethink-argo.git
          revision: HEAD
          directories:
            - path: kustomize/*
      
      # cluster generator, 'child' #2
      # this can also be '-clusters: {}' to select them all. However, less readable.
      - clusters:
          selector:
            matchLabels:
              argocd.argoproj.io/secret-type: cluster
```
Here's an example of an item generated by this matrix:

```
- name: staging
  server: https://1.2.3.4
  path: kustomize/nginx
  path.basename: nginx
```
And here's the template doing so:

```
template:
  metadata:
    name: '{{ .path.basename }}'
  
    ## ... Ommitted ...##
  spec:

    ## ... Ommitted ...##

    # 'name' field of the Secret
    # for example production
    # you could also use labels, for more flexibility 
    project: '{{ .name }}'
    source:
      path: '{{ .path }}/overlays/{{ .name }}'
    destination:
      # 'server' field of the secret
      # for example https://prod.rethink-argo.develeap.com:6443
      server: '{{ .server }}'
      namespace: '{{ .path.basename }}'
```
# 




<!--- Eraser file: https://app.eraser.io/workspace/F95eLPbElWDqPYpdYBwV --->