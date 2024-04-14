# README

![image.png](https://eraser.imgix.net/workspaces/F95eLPbElWDqPYpdYBwV/TQmgywa6AXge7WJMnlClJmSiIXA2/QhWnNXCJ2CqqEgMSGqx1c.png?ixlib=js-3.7.0 "image.png")

# What is [Argo]([﻿argoproj.github.io/](https://argoproj.github.io/))?

Open source tools for Kubernetes to run workflows, manage clusters, and do GitOps right.

As of today, most significant tooling by Argo are:

- CD (with Notifications out-of-the-box)
- Events
- Workflows
- Rollouts

---

## What's the plan?

We are going to start by talk about basic and advanced ArgoCD features:

- ApplicationSet - What is it and how to use it ?
- Notifications 101
- Sync waves for the typical project
- Multi-Cluster deployment best practices
- Webhooks, polling - why and why not ?
- Different Sync options
  Then we will try our Argo Rollouts and Argo Workflows, and examine the use cases, benefits.

## The Goal

![image.png](architecture.png)

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

---

## Before we dive in: where does argo store it's objects?

Argo CD is largely stateless. All data is persisted as Kubernetes objects, which in turn is stored in Kubernetes' etcd.

## GitHub Integration: Webhook vs. Polling

By design, ArgoCD uses polling to sync the desired state with the actual state. However, something we might want / need to use webhook.

Let's compare the two:

|                                 | Polling | Webhook |
| ------------------------------- | ------- | ------- |
| Requires public ArgoCD endpoint | x       | v       |
| Automatically triggers sync     | v       | x       |
| Diff up to 3 minutes            | v       | x       |
| Easy to setup                   | v       | v       |

#### [﻿Webhook setup](https://argo-cd.readthedocs.io/en/stable/operator-manual/webhook/#git-webhook-configuration):

In order for the webhook to work as expected, a few thing must be in order. Firstly, our ArgoCD endpoint must be available for GitHub, so it could invoke it from outside our environment. Then, under repository `Settings > Webhooks > Add Webhook` set the following:

```
Endpoint: www.rethink-argocd.develeap.com/api/webhook
Content-type: application/json
Secret: my-super-secret
```

And set the trigger according to your needs.

Then, edit / patch the kubernetes secret `argocd-secret` (which reside the same namespace as our argocd server, `namespace: argocd` by default) manifest to contain the same webhook secret, and apply. Then same pattern of using secret available to argocd repeats itself in this lesson.

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: argocd-secret
  namespace: argocd
type: Opaque
data:
---
stringData:
  # github webhook secret
  webhook.github.secret: my-super-secret
```

_\*Patch operations are easier with Kustomize._

_\*\*Kustomize can also be integrated with SOPS._

### Configure the repository

Althought we have configured the webhook which seems like all the integration between GitHub and ArgoCD, it is infact only the configuration allowing to github reach out to argo and say "Hey argo! Start sync, please".

Setting a repository is quite simple, we'll stick to the SSH method. Again, notice the unique annotation!

```yaml
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

```yaml
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

\*Again, Kustomize can make our life easier by using secretGenerators.

##### Project and Policies

Creating a project declaratively requires an `AppProject` manifest, and for each project we would have to declare and assign the permissions policies.

```yaml
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
    - name: developmet-devops
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

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-rbac-cm
  namespace: argocd
data:
  scopes: "[groups]" # include 'emails' if using OIDC
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

```yaml
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
      name: "{{ .path.basename }}"

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
        path: "{{ .path }}"
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
        namespace: "{{ path.basename }}"
```

Now that we understand what is an ApplicationSet, it's abilities, structure and so forth, let's apply our knowledge to match our desired architecture.

This time, the major difference will be at the generator, we will use `matrix` to mix and match both clusters and applications.

we are going to match each Kustomize overlay to the matching cluster, in the match project.

```yaml
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

```yaml
- name: staging
  server: https://1.2.3.4
  path: kustomize/nginx
  path.basename: nginx
```

And here's the template doing so:

```yaml
template:
  metadata:
    name: "{{ .path.basename }}"
    ## ... Ommitted ...##
  spec:
    ## ... Ommitted ...##

    # 'name' field of the Secret
    # for example production
    # you could also use labels, for more flexibility
    project: "{{ .name }}"
    source:
      path: "{{ .path }}/overlays/{{ .name }}"
    destination:
      # 'server' field of the secret
      # for example https://prod.rethink-argo.develeap.com:6443
      server: "{{ .server }}"
      namespace: "{{ .path.basename }}"
```

## Sync waves, and Sync options

The are both related to sync, however quite different.

Sync option are the different syncing options provided by ArgoCD for us to decided how it should behave on sync occasions.

Sync waves on the other hand, are meant to determine when to sync, at what stage, which is also called "wave".

### The different Sync Options

These could be set either by the `[﻿argocd.argoproj.io/sync-options](https://argocd.argoproj.io/sync-options)`

separated by `,` or alternatively, set under the spec.syncPolicy.syncOptions `spec.syncPolicy.syncOptions` field in the application manifest. Most annotations could also be used on specific resources, and not only applications.

```yaml
spec:
  syncPolicy:
    syncOptions:
      - Prune=false # Do no prune, e.g leave a Pod which finished it's execution ( completed 0/1)
      - Validate=false # Do no validate the kubernetes types
      - SkipDryRunOnMissingResource=true # Meant to ignore custom CRDs which argo can't evaluate their health
      - Delete=false # Prevent argo from destroying, e.g PVC
      - ApplyOutOfSyncOnly=true # Sync only our-of-sync resources
      - PrunePropagationPolicy=foreground # Use a foreground process
      - PruneLast=true # Prune as a final step, after all "waves", etc
      - CreateNamespace=true # Allow for namespace to be created in nonexistent
      - ServerSideApply=true # Apply using server side, meant to be used in special cases, like 'too big' annotations.
      - Replace=true # Replace the entire resource, instead of applying the diff.
      - FailOnSharedResource=true # Fail in case of shared resource use by different applications.
      - RespectIgnoreDifferences=true # Tell argo to ignore specific differences between desired and actual stage.
```

### Sync Waves

Argo sync process is complicated, and has the following precedence:

1. Sync Phase (PreSync/Sync/PostSync/SyncFail/PostDelete)

![image.png](https://eraser.imgix.net/workspaces/F95eLPbElWDqPYpdYBwV/TQmgywa6AXge7WJMnlClJmSiIXA2/UPf9n9ugrCuUh8Dd_B8Ca.png?ixlib=js-3.7.0 "image.png")

2. Sync Wave (Set be values, lowest first)

3. By Kind (Namespace first, then other kubernetes resource types, and eventually CRDs)

4. By name (alphabetically).

Sync wave are used to apply different configurations in stages within a Phase, for example, only apply the `demo` application's deployment after `vault` application had been applied and the `my-secret` has been created.

Le'ts look at another example:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: applicationset-stage-1
  namespace: argocd
spec:
  ## ... Ommitted ...##
  template:
    metadata:
      name: '{{ .path.basename }}'
      namespace: argocd
      annotations:
        argocd.argoproj.io/sync-wave: "1"
 ## ... Ommitted ...##
 ---
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: applicationset-stage-2
  namespace: argocd
spec:
  ## ... Ommitted ...##
  template:
    metadata:
      name: '{{ .path.basename }}'
      namespace: argocd
      annotations:
        argocd.argoproj.io/sync-wave: "2"
  ## ... Ommitted ...##
```

### Sync Windows

Under the AppProject setting we can define the desired sync times, referred by argo as "sync windows". Here's an example of a sync window denying all sync times, while allowing manual sync, using the UI to the cli.

```yaml
syncWindows:
  - kind: deny
    schedule: "* * * * *"
    duration: 1h
    applications:
      - "*"
    clusters:
      - production cluster
    manualSync: true
```

Putting in all together: the following example allows the dev environment to sync on workdays on work time, while denying any sync ops during Thursdays throught Saturday. Manual sync allow.

```yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  annotations:
    argocd-autopilot.argoproj-labs.io/default-dest-server: https://kubernetes.default.svc
    argocd.argoproj.io/sync-options: PruneLast=true
    argocd.argoproj.io/sync-wave: "-2"
  name: development
  namespace: argocd
spec:
  # Allow syncinng from 7am to 8pm on weekdays, but deny on weekends
  - kind: allow
    schedule: "* 7-20 * * 0-4"
    duration: 1h
    applications:
      - "*"
    clusters:
      - development cluster
    manualSync: true
```

## Notifications

Argo notifications used to be a independent project by Argo Project, which served as an extension to the basic ArgoCD ecosystem. It is meant to provide a unified notifications system, according to different events, which could be quite custom to ArgoCD. An ArgoCD Application's failed sync operation, for example.

It uses web-hooks to integrate and notify different notification services according to the specified rules. Let's take a look at an example:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  annotations:
    notifications.argoproj.io/subscribe.app-sync-failed.slack: "<my-slack-channel>"
```

Setup is quite simple, all your need is an secret holding the credentials. Each notification service requires different fields. Here's a slack example:

```yaml
# The kubernetes secret
apiVersion: v1
kind: Secret
metadata:
  name: <secret-name>
stringData:
  slack-token: <Oauth-access-token>
---
# The ArgoCD notification configurations
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-notifications-cm
data:
  # This tells argo `notification's controller` how to find and use the credentials, whenever the slack service is being used.
  service.slack: |
    token: $slack-token
```

You could also use custom messaging templates, like so:

```yaml
template.app-sync-failed: |
message: |
  Application {{.app.metadata.name}} sync is {{.app.status.sync.status}}.
  Application details: {{.context.argocdUrl}}/applications/{{.app.metadata.name}}.
slack:
  attachments: |
    [{
      "title": "{{.app.metadata.name}}",
      "title_link": "{{.context.argocdUrl}}/applications/{{.app.metadata.name}}",
      "color": "#ff0000",
      "fields": [{
        "title": "Sync Status",
        "value": "{{.app.status.sync.status}}",
        "short": true
      }, {
        "title": "Repository",
        "value": "{{.app.spec.source.repoURL}}",
        "short": true
      }]
    }]
  # Aggregate the messages to the thread by git commit hash
  groupingKey: "{{.app.status.sync.revision}}"
  notifyBroadcast: true
```

Here's an example of a successful sync notification via slack:

![image.png](https://eraser.imgix.net/workspaces/F95eLPbElWDqPYpdYBwV/TQmgywa6AXge7WJMnlClJmSiIXA2/USa7OY5y_JlT8JH2rO7o0.png?ixlib=js-3.7.0 "image.png")

### Behind the scenes

The ArgoCD Notification extention is simple a wrapper around Kubernetes Jobs + ArgoCD sync phases, and can simply be replaced with using:

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  generateName: app-slack-notification-fail-
  annotations:
    argocd.argoproj.io/hook: SyncFail
    argocd.argoproj.io/hook-delete-policy: HookSucceeded
spec:
  template:
    spec:
      containers:
        - name: slack-notification
          image: curlimages/curl
          command:
            - "curl"
            - "-X"
            - "POST"
            - "--data-urlencode"
            - 'payload={"channel": "#somechannel", "username": "hello", "text": "App Sync failed", "icon_emoji": ":ghost:"}'
            - "https://hooks.slack.com/services/..."
      restartPolicy: Never
  backoffLimit: 2
```

However, it allows for a more unified experience, and offer a [﻿catalog](https://argocd-notifications.readthedocs.io/en/stable/catalog/), containing triggers and templates ready to go, without the need to custom create and configure one yourself. Also, there's a metrics endpoint for prometheus scraping, and they offer a granafa dashboard json file.

## [﻿Debugging notifications](https://argocd-notifications.readthedocs.io/en/stable/troubleshooting/)﻿

When in comes to debugging issue with notifications / trigger there's a cli tool mean to help and get better information about the process.

```bash
argocd-notifications template notify app-sync-failed guestbook --recipient slack:my-team-channel
```

---

## Argo [﻿Rollouts](https://argo-rollouts.readthedocs.io/en/stable/)﻿

The rollout project is design to reduce the overhead required the different deployment approaches. Whether you organization use blue-green or canary deployments for a given service, argo rollout can do it with ease.

No addition deployments needed, no services and load balancing, all in a simple Rollout manifest. Rollouts will replace our `Kind: Deployment` manifest, with the addition of a `strategy` specifications added.

`nvim -d deployment.yaml rollout.yaml` results with:

![Screenshot 2024-04-03 at 16.37.27.png](https://eraser.imgix.net/workspaces/F95eLPbElWDqPYpdYBwV/TQmgywa6AXge7WJMnlClJmSiIXA2/lh-w8EcNJm4_jTpf-vVjO.png?ixlib=js-3.7.0 "Screenshot 2024-04-03 at 16.37.27.png")

The following is an example of a canary deployment:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: rollout-canary
spec:
  replicas: 5
  revisionHistoryLimit: 2
  selector:
    matchLabels:
      app: rollout-canary
  template:
    metadata:
      labels:
        app: rollout-canary
    spec:
      containers:
        - name: rollouts-demo
          image: argoproj/rollouts-demo:blue
          imagePullPolicy: Always
          ports:
            - containerPort: 8080
  strategy:
    canary:
      steps:
        - setWeight: 20
        # The following pause step will pause the rollout indefinitely until manually resumed.
        # Rollouts can be manually resumed by running `kubectl argo rollouts promote ROLLOUT`
        - pause: {}
        - setWeight: 40
        - pause: { duration: 40s }
        - setWeight: 60
        - pause: { duration: 20s }
        - setWeight: 80
        - pause: { duration: 20s }
```

In this example, a rollout will only "rollout" 1 replica (20% of the desired total replicas) of a new version, until it is manually "promoted" by either using the "promote" button in the UI or by leveraging the cli with `kubectl argo rollouts promote ROLLOUT_NAME` .

Rollout greatest benefit is when end-to-end or any other types of tests need to be run and set the promotion according to the test results.

Similar to healthchecks in Docker, or using probes in kubernetes, just a little easier and greater room to move. Let's take a look into an example:

```yaml
# This AnalysisTemplate will run a Kubernetes Job every 5 seconds, with a 50% chance of failure.
# When the number of accumulated failures exceeds failureLimit, it will cause the analysis run to
# fail, and subsequently cause the rollout or experiment to abort.
kind: AnalysisTemplate
apiVersion: argoproj.io/v1alpha1
metadata:
  name: random-fail
spec:
  metrics:
    - name: random-fail
      count: 2
      interval: 5s
      failureLimit: 1
      provider:
        job:
          spec:
            template:
              spec:
                containers:
                  - name: sleep
                    image: alpine:3.8
                    command: [sh, -c]
                    args: [FLIP=$(($(($RANDOM%10))%2)) && exit $FLIP]
                restartPolicy: Never
            backoffLimit: 0
---
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: rollout-canary
spec:
  ## ... Ommitted ... ##
  strategy:
    canary:
      steps:
        - setWeight: 20
        # An AnalysisTemplate is referenced at the second step, which starts an AnalysisRun after
        # the setWeight step. The rollout will not progress to the following step until the
        # AnalysisRun is complete. A failure/error of the analysis will cause the rollout's update to
        # abort, and set the canary weight to zero.
        - analysis:
          templates:
            - templateName: random-fail
        - setWeight: 40
        - pause: { duration: 40s }
        - setWeight: 60
        - pause: { duration: 20s }
        - setWeight: 80
        - pause: { duration: 20s }
```

I love rollouts, however I hate shifting from the simple yet classy kubernetes Deployment manifest, and removing it from every chart and re-writing templates accordingly seems like to much it integrate it.

So I'd like to share a better approach, with the following strategy:

1. Set the deployment's `replica` filed to `0` , so we can allow the `rollout` take charge of them.
2. Create a separate `rollout.yaml` with the rolling strategy set, referencing the original deployment.

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app.kubernetes.io/instance: rollout-canary
  name: simple-deployment
spec:
  # Replicas set to 0, to be controlled by the rollout instead.
  replicas: 0
  selector:
    matchLabels:
      app: simple-deployment
  template:
    metadata:
      labels:
        app: simple-deployment
    spec:
      containers:
        - name: nginx
          image: nginx:latest
          imagePullPolicy: Always
          ports:
            - containerPort: 80
---
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: simple-deployment-rollout
spec:
  replicas: 5
  revisionHistoryLimit: 2
  workloadRef:
    apiVersion: apps/v1
    kind: Deployment
    name: simple-deployment
  strategy:
    ## ... Ommitted ... ##
```

---

## Argo Workflows

Another wrapper from Argo's familiy, meant to complicate thing further by having weird funky syntax. I really cannot recommend it in comparison with github actions / jenkins, however it's key benefits might be actually running and / or setting in on-prem for CI/CD, data processing, ML, etc without the overhead of golden images and such.

---

# ArgoCD [﻿Autopilot](https://github.com/argoproj-labs/argocd-autopilot)﻿

Relatively new project by the Argo team, first released in 2021, meant to help with bootstrapping and onboarding of a new repository while following GitOps best practices. It's cli acts as a wrapper to usual argocd cli tool using common practices and flagging system. So if you are new to git or argocd and wish to make your future easier by following best methods and compliance, be sure to check it out.

This cli tool leveraged your `.gitconfig` and `.kubeconfig` , and a repository's API KEY.

It will install ArgoCD onto your cluster, while creating manifest and folder structure in your git repository.

The cli offer projects management (create, delete, list), application managment, and bootstrapping (install/uninstall). It's great to use as a base template of even as an Observability over ArgoCD using ArgoCD, but permissions and cluster/repository secret should still be declared separately (if you are following the segregated approach).

## KSOPS (Kustomize + SecretsOPerationS )

Sops is very similar to the well known "Sealed Secrets", the key difference is that in sops you own / provide you own encryption key (age, gpg, kms, etc) and has great integrations with many tools such as Kustomize and Terragrunt.

[﻿Pre-requisites for argo integration](https://github.com/viaduct-ai/kustomize-sops#argo-cd-integration-)

Let's begin with a quick guide about [﻿setting it up](https://github.com/viaduct-ai/kustomize-sops#1-download-and-install-ksops):

- Download ksops:

```bash
source <(curl -s https://raw.githubusercontent.com/viaduct-ai/kustomize-sops/master/scripts/install-ksops-archive.s
```

- Set up sops config according to your flavor:

```yaml
#creation rules are evaluated sequentially, the first match wins
creation_rules:
  - unencrypted_regex: ^(apiVersion|metadata|kind|type)$
  - age: age1zge2l5uxpph0x3u0qg53h8jg8mf0m6kce249lv73nv7e9mwc3chq92f6cj
```

- Set up the decryption generator:

```yaml
# Creates a local Kubernetes Secret
apiVersion: viaduct.ai/v1
kind: ksops
metadata:
  # Specify a name
  name: example-secret-generator
  annotations:
    config.kubernetes.io/function: |
      exec:
        # if the binary is in your PATH, you can do
        path: ksops
        # otherwise, path should be relative to manifest files, like
        # path: ../../../ksops
files:
  - ./secret.enc.yaml
```

- Patch the argocd-repo-server to have both ksops plugin, and have the decryption key available to use. Here's

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: argocd-repo-server
  namespace: argocd
spec:
  template:
    spec:
      volumes:
        - name: custom-tools
          emptyDir: {}
      initContainers:
        - name: install-ksops
          image: viaductoss/ksops:v4.3.1
          command: ["/bin/sh", "-c"]
          args:
            - echo "Installing KSOPS...";
              mv ksops /custom-tools/;
              mv kustomize /custom-tools/;
              echo "Done.";
          volumeMounts:
            - mountPath: /custom-tools
              name: custom-tools
      containers:
        - name: argocd-repo-server
          volumeMounts:
            - mountPath: /usr/local/bin/kustomize
              name: custom-tools
              subPath: kustomize
              # Verify this matches a XDG_CONFIG_HOME=/.config env variable
            - mountPath: /.config/kustomize/plugin/viaduct.ai/v1/ksops/ksops
              name: custom-tools
              subPath: ksops
          # 4. Set the XDG_CONFIG_HOME env variable to allow kustomize to detect the plugin
          env:
            - name: XDG_CONFIG_HOME
              value: /.config
            ### ... Ommitted ... ###
```

- Create a secret holding the key: `cat key.txt| kubectl create secret generic sops-age --namespace=argocd --from-file=keys.txt=/dev/stdin` .
- Make sure the key is loaded into the deployment, and set the reguired environment variables (specific for age):

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: argocd-repo-server
  namespace: argocd
spec:
  template:
    spec:
      volumes:
        - name: sops-age
          secret:
            secretName: sops-age
      containers:
        - name: argocd-repo-server
          volumeMounts:
            - mountPath: /.config/sops/age/keys.txt
              name: sops-age
          ### ... Ommitted ... ###
          env:
            - name: SOPS_AGE_KEY_FILE
              value: /.config/sops/age/key.txt
```

- Create the kustomization file to apply the decrypted files with argo:

```yaml
apiVersion: viaduct.ai/v1
kind: ksops
metadata:
  # Specify a name
  name: secret-generator
  annotations:
    [﻿config.kubernetes.io/function:](https://config.kubernetes.io/function:) |
      exec:
        # if the binary is in your PATH, you can do
        # path: /usr/local/bin/ksops
        # Otherwise point it at the plugin
        path: /.config/kustomize/plugin/viaduct.ai/v1/ksops/ksops
files:
- development-cluster.enc.yaml
- production-cluster.enc.yaml
```

- Apply using kustomize and the required flags:
  `kustomize build --enable-alpha-plugins --enable-exec .`
  In your interested in learning more about sops and setting it up, check out my other repository, named [﻿toolbox](https://github.com/zMynxx/Toolbox/tree/feature/sops-aghe/mozilla-sops/age).

# Common Issues and solutions

- "Unable to extract token claims" - The connection protocol for login is not set correctly, and the grpc-web-root-path is not set.

```bash
ERRO[0001] finished unary call with code Unknown         error="unable to extract token claims" grpc.code=Unknown grpc.method=UpdatePassword grpc.service=account.AccountService grpc.start_time="2023-12-20T07:47:58Z" grpc.time_ms=0.042 span.kind=server system=grpc
FATA[0001] rpc error: code = Unknown desc = unable to extract token claims
```

Solution: `argocd login <hostname> --username admin --grpc-web-root-path /`

- "response.WriteHeader on hijacked connection" - When trying to use Web Terminal

```bash
2023/07/02 11:07:31 http: response.WriteHeader on hijacked connection from github.com/argoproj/argo-cd/v2/server/application.(*terminalHandler).ServeHTTP (terminal.go:245)
2023/07/02 11:07:31 http: response.Write on hijacked connection from fmt.Fprintln (print.go:285)
```

Solution:

1. Make sure the following Role/ClusterRole permissions are available:

The Role/ClusterRole is `argocd-server`, unless your trying to exec to another cluster workloads, then it's `argocd-manager-role` ClusterRole.

```yaml
- apiGroups:
    - ""
  resources:
    - pods/exec
  verbs:
    - create
```

2. Make sure the role you're trying to exec with has the correct permissions: (project level permissions)

```csv
p, role:myrole, exec, create, */*, allow
```
