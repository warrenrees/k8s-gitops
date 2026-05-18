# Namespace Migration Runbook (Phase 3)

Move the ~32 workloads currently in the `default` namespace into per-area
namespaces matching the repo's folder structure. ~68 manifest files reference
`namespace: default`.

## What makes this safe (verified)

- **All PVs are `persistentVolumeReclaimPolicy: Retain`** (Longhorn *and* NFS) —
  deleting a PVC does **not** destroy data; the PV survives for re-binding.
- **Both Gateways use `allowedRoutes.namespaces.from: All`** — HTTPRoutes work
  from any namespace; no Gateway change needed.
- **Cilium L2/LB-IPAM is cluster-wide** — Services keep their `loadBalancerIP`
  and re-announce the same IP regardless of namespace.
- **No per-app `kustomization.yaml`** — Flux auto-generates one for
  `./clusters/production`. Namespace is set per-resource via `metadata.namespace`;
  there is no kustomize `namespace:` transformer to flip. Every resource of an app
  must be edited individually.

## Target namespace mapping

| App | → Namespace | Storage | PVCs | LB IP | Notes |
|---|---|---|---|---|---|
| double-take | automation | Longhorn | pvc-doubletake | — | |
| esphome | automation | Longhorn | pvc-esphome-data | — | hostNetwork + privileged (USB) |
| frigate | automation | LH + NFS | pvc-frigate-config, pvc-frigate-media | 10.0.0.244 | hostNetwork; route → identity outpost |
| govee2mqtt | automation | none | — | — | stateless; hostNetwork |
| home-assistant | automation | none | — | — | ExternalName Service only (HA runs off-cluster) |
| influxdb2 | automation | Longhorn | pvc-influxdb2-data | — | StatefulSet |
| mosquitto | automation | Longhorn | pvc-mosquitto-data, pvc-mosquitto-configinc | 10.0.0.245 | |
| music-assistant | automation | Longhorn | pvc-music-assistant-data | — | hostNetwork |
| immich (server, database, machine-learning, redis) | media | LH + NFS | pvc-immich-db (LH), pvc-immich-data (NFS) | — | **migrate the 4 components together** |
| plex | media | LH + NFS | pvc-plex-config (LH); shared NFS below | 10.0.0.30 | |
| sabnzbd | media | Longhorn | pvc-sabnzbd-config | — | mounts shared NFS |
| sonarr / radarr / lidarr | media | Longhorn | pvc-{sonarr,radarr,lidarr}-config | — | mount shared NFS |
| ombi | media | Longhorn | pvc-ombi-config | — | route → identity outpost |
| maintainerr | media | Longhorn | pvc-maintainerr | — | |
| tautulli | media | Longhorn | pvc-tautulli-config | — | |
| wyzebridge | media | Longhorn | pvc-wyzebridge-config | — | |
| rsyncd-backups | media | NFS | pvc-rsyncd-backups | 10.0.0.249 | |
| openwakeword | media | none | — | 10.0.0.247 (shared) | stateless |
| piper | media | Longhorn | pvc-piper-data | 10.0.0.247 (shared) | |
| whisper | media | Longhorn | pvc-whisper-data | 10.0.0.247 (shared) | |
| minecraft-server / bodhi / warren | games | Longhorn | pvc-minecraft, pvc-minecraft-bodhi, pvc-minecraft-warren | 10.0.0.34/.248/.250 | |
| oscar | oscar | LH + NFS | pvc-oscar-data (LH), pvc-oscar-sdcard (NFS) | — | |
| ps | utilities | none | — | — | stateless; route → identity outpost |

**Shared NFS media PVCs** — `pvc-media-videos`, `pvc-media-music`,
`pvc-media-photos`, `pvc-photo`, `pvc-media-downloads` — are mounted by plex /
sabnzbd / *arr. All those apps land in `media`, so each shared PVC migrates to
`media` **once**, with every consumer scaled down during that step.

### Items needing a decision before starting

- **pihole** — lives in `core/pihole` (infra), runs in `default`, LB `10.0.0.35`.
  Pick a home: a new `networking` namespace, or leave it as the lone `default`
  resident. Not in the table above pending that call.
- **vaultwarden** — manifests are scattered: `identity/vaultwarden-release.yaml`
  (sets `namespace: default`) + `automation/home-assistant/vaultwarden-httproute.yaml`.
  Recommend consolidating into one folder and targeting the `identity` namespace.
- **metermon** — **not found anywhere in the repo** despite running in `default`.
  It is likely a manually-applied (non-GitOps) workload. Import it into the repo
  first, or it can't be migrated via GitOps.
- **deepstack / deepstackui** — retired (scaled to 0). Recommend **deleting** it
  from repo + cluster rather than migrating.

## Pre-flight (once, before any app moves)

1. Add `Namespace` manifests: `media`, `automation`, `games`, `utilities`,
   `oscar` (+ `networking` if chosen for pihole).
2. Add a `LimitRange` to each new namespace — copy the pattern from
   `clusters/production/core/limitranges/`.
3. Extend the authentik outpost `ReferenceGrant`s. Today `identity` has
   `outpost-from-default`; frigate, ombi and ps use the forward-auth outpost and
   are moving out of `default`. Add `from` entries (or new grants) for `media`,
   `automation`, and `utilities`.
4. Confirm a current Longhorn backup target exists; the daily recurring job is
   in place, but take an on-demand backup of each volume right before migrating it.
5. **Authentik proxy-provider upstreams.** Apps behind the authentik outpost
   (`frigate`, `ombi`, `ps`) have their upstream host configured *inside Authentik*
   (Applications → Providers → "Internal host"), not in git — e.g.
   `http://frigate-tcp.default.svc.cluster.local:8971`. When the app moves
   namespace, update that host to `<svc>.<new-ns>.svc.cluster.local` or the
   outpost returns **Bad Gateway**. Do this right after the app's pods are up
   in the new namespace.

## Migration procedure

### A. Stateless apps — `govee2mqtt`, `openwakeword`, `ps`, (`metermon` once imported)

1. Edit `metadata.namespace` on every resource in the app's manifests
   (Deployment, Service, HTTPRoute, ConfigMaps).
2. **SealedSecrets must be re-sealed, not moved** — they are sealed with a strict
   namespace+name scope, so a moved SealedSecret fails to decrypt. Re-seal from
   the live (already-decrypted) Secret:
   `kubectl get secret <name> -n default -o json | jq '{apiVersion,kind,type,metadata:{name:.metadata.name,namespace:"<new-ns>"},data}' | kubeseal --controller-name sealed-secrets-controller --controller-namespace kube-system --format yaml`
   → replace the SealedSecret manifest with the output.
3. Move the HTTPRoute with the app — its `backendRef` stays same-namespace, so no
   ReferenceGrant is needed (except apps using the identity outpost — handled in
   pre-flight).
4. Commit. Flux creates resources in the new namespace and prunes the `default`
   copies. Brief restart, no data risk.

### B. Stateful apps — Longhorn PVC (one app at a time)

For each **raw-manifest** app (e.g. sonarr, radarr, lidarr, tautulli,
maintainerr, double-take, esphome, mosquitto, music-assistant, ombi, wyzebridge,
plex-config, piper, whisper, oscar-data, immich-db). HelmRelease-based apps
(minecraft, influxdb2, pihole) use **section E** instead:

1. **Back up** the Longhorn volume (on-demand backup/snapshot).
2. Note the bound PV name (`kubectl get pvc <pvc> -n default -o jsonpath='{.spec.volumeName}'`).
3. Scale the workload to 0 so the Longhorn volume detaches.
4. Delete the old PVC in `default`. The PV → `Released` (data retained).
5. Clear the stale claim: `kubectl patch pv <pv> -p '{"spec":{"claimRef":null}}'`
   → PV becomes `Available`.
6. In the repo, edit the app's manifests to the new namespace, and on the **PVC
   manifest** add `spec.volumeName: <pv>` so the new PVC statically binds the
   existing PV (keep storageClassName / accessModes / size identical).
7. Commit; Flux creates the namespace-moved resources. Verify the PVC is `Bound`
   to the original PV and the app starts with its data intact.
8. Remove the temporary `volumeName` pin on a later cleanup pass if desired (Flux
   keeps the binding regardless).

### C. Stateful apps — NFS PVC (`frigate-media`, `immich-data`, `oscar-sdcard`,
`rsyncd-backups`, and the shared `media-*` PVCs)

Same claimRef dance as B, but NFS PVs are not block-attached — no detach wait.
The new PVC manifest still needs `spec.volumeName: <pv>`.

For the **shared media PVCs**: scale down **all** consumers (plex, sabnzbd,
sonarr, radarr, lidarr) first, migrate the PVC to `media`, then bring the apps
back up in `media`.

### D. immich (multi-component)

Migrate `immich-server`, `immich-database`, `immich-machine-learning` and
`immich-redis` as one unit into `media`: scale all four down, migrate
`pvc-immich-db` (Longhorn, per B) and `pvc-immich-data` (NFS, per C), move all
four sets of manifests, bring them up together.

### E. HelmRelease-based apps (`minecraft-server`, `minecraft-bodhi`, `minecraft-warren`, `influxdb2`, `pihole`)

These deploy via a Flux **HelmRelease** (the object itself lives in
`flux-system`) with `targetNamespace: default`. Two complications vs. raw
manifests:

- Migrating means changing `targetNamespace`. Doing that *in place* can leave
  the release **orphaned** in the old namespace — so **delete and recreate** the
  HelmRelease instead.
- Their `existingClaim` PVCs were created **directly in Longhorn** and are
  **not in the repo** (drift). Each must be created in the target namespace and
  imported as a PVC manifest.

Procedure (suspend once for the batch, then per app):

1. `flux suspend kustomization flux-system` — freezes the kustomize-controller
   so it cannot re-create the HelmRelease mid-migration.
2. Back up the Longhorn volume (snapshot).
3. `kubectl scale deploy <app> -n default --replicas=0` — volume detaches.
   **Downtime starts.**
4. Delete the old PVC in `default`; `kubectl patch pv <pv> -p
   '{"spec":{"claimRef":null}}'` → PV `Available` (data retained — `Retain`).
5. `kubectl delete helmrelease <app> -n flux-system` — helm-controller
   uninstalls the release from `default` (removes its Deployment/Service).
6. In the repo: set the HelmRelease `targetNamespace` to the new namespace, and
   **add a PVC manifest** in that namespace with `spec.volumeName: <pv>` (this
   imports the drift PVC into GitOps). Commit + push.
7. `flux reconcile source git flux-system` **first** (fetch the new commit),
   *then* `flux resume kustomization flux-system`. Resuming triggers an immediate
   reconcile — if the source still holds the pre-change revision, Flux reconciles
   that **stale** revision and briefly recreates the HelmRelease in the *old*
   namespace (pods land back in `default`, Pending — their PVCs are gone). With
   the source current first, the resume reconciles the correct revision. Flux
   recreates the HelmRelease targeting the new namespace + the PVC; helm-controller
   installs the chart and the PVC binds the existing PV. **Downtime ends when Ready.**
8. Verify data intact and the app reachable on its LB IP.

## Suggested sequencing

1. Pre-flight (namespaces, LimitRanges, ReferenceGrants).
2. Resolve the four decision items (pihole, vaultwarden, metermon, deepstack).
3. Stateless apps — batch.
4. `games` (3 minecraft apps) — self-contained, low blast radius — good first
   stateful pass to validate the procedure.
5. `automation` apps, one at a time.
6. `media` — last and most carefully: do the *arr apps and tautulli/maintainerr,
   then the shared-NFS group (plex + sabnzbd + *arr media mounts), then immich.
7. `oscar`, `utilities`.
8. After each namespace is fully populated, verify routes resolve and apps are
   healthy before moving on.

## Rollback

Because every PV is `Retain`: to roll an app back, scale it down, delete the new
PVC, clear the PV `claimRef`, recreate the PVC in `default` with
`volumeName: <pv>`, and revert the manifest changes. No data is lost at any step.

## Verification (per app and at the end)

- `kubectl get pods -A` — `default` empties of apps; each app `Ready` in its
  new namespace.
- `kubectl get pvc -A` — every migrated PVC `Bound` to its original PV.
- HTTPRoutes resolve (apps reachable on their hostnames); LB IPs unchanged.
- `flux get kustomizations -A` — clean, no prune errors.

## Phase 4 (security) — follows this

Once apps are in real namespaces, Phase 4 becomes tractable: per-namespace
default-deny `CiliumNetworkPolicy`, `securityContext` defaults, and
`pod-security.kubernetes.io/enforce` labels. Worth its own runbook after Phase 3.
