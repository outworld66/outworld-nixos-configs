# Stoat on Rico

Stoat is hosted at `https://stoat.outworld66.ru`. The NixOS configuration runs its API, event gateway, upload service, metadata proxy, and web client as a Docker Compose stack managed by systemd. MongoDB and uploaded files persist under `/var/lib/stoat` and `/srv/stoat/files`; the latter uses the merged `/srv` mount.

The forked API enables Pocket ID OpenID Connect. The API accepts verified email addresses only and links them to existing Stoat accounts; OIDC does not create accounts. The callback is `https://stoat.outworld66.ru/api/auth/session/oidc/callback`. Pocket ID permits members of the `stoat-admin` and `stoat-user` groups through Pomerium. Rico's private Nix configuration maps its existing administrator to `stoat-admin`; add other users to `stoat-user` in Pocket ID. Once allowed through the gateway, users can create a local account, then choose “Continue with single sign-on.” Stoat registration remains open at the API, but its public hostname is group-restricted by Pomerium.

The first deployment generates persistent RabbitMQ, S3, file-encryption, and VAPID secrets in `/var/lib/stoat/secrets.env`. Pocket ID provisions the `stoat` OIDC client and writes its secret to `/var/lib/stoat/oidc.env`. These runtime files are root-owned and are not stored in Git or the Nix store. Back up `/var/lib/stoat` and `/srv/stoat/files` together.

Voice and video calling are disabled in this deployment because Rico's existing LiveKit listener is reserved for MatrixRTC. To verify the service, check `systemctl status stoat`, `docker ps --filter label=com.docker.compose.project=stoat`, and `curl https://stoat.outworld66.ru/.well-known/stoat`. Recover with `systemctl restart stoat`; roll back the system generation with the documented server rollback procedure.
