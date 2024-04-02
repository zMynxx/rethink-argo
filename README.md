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
For the sake of readability, ease of search, debug, use and operate, and also to fully match the desired state describe in the Goal image, we will separate each and every cluster with it's own project and policies.

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
  server: "https://dev.develeap.rethink-argo.com:6443"
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

      groups: #OIDC Groups 
        - devops
        - developers
        - finops
        - mlops

  # Project description
  description: development environment

  # Allow manifests to deploy from out GitOps repos.
  sourceRepos:
    - https://github.com/develeap/rethink-argo.git

  destinations:
    ## Allow all access
    - namespace: "*"
      server: https://dev.develeap.rethink-argo.com:6443
      name: dev

  clusterResourceWhitelist:
    - group: "*"
      kind: "*"

  namespaceResourceWhitelist:
    - group: "*"
      kind: "*"

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
  policy.default: role:readonly
  policy.csv: |
    p, proj:development:developer, clusters, get, *, allow
    p, proj:development:developer, repositories, get, *, allow
    p, proj:development:developer, projects, get, *, allow

    g, your-github-org:your-team, role:org-admin
```




<!--- Eraser file: https://app.eraser.io/workspace/F95eLPbElWDqPYpdYBwV --->