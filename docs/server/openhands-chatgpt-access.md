# OpenHands ChatGPT subscription access

Every OIDC user can connect a personal ChatGPT subscription in **Settings → LLM Profiles**. The OAuth file is stored under that user's private server directory and mounted only into that user's conversation runtime.

Administrators connect the shared subscription from the same card. They can grant or revoke access using a user's OIDC account ID, which users can copy from the card. A granted user can select **Use shared subscription** or **Use my subscription**. Without a saved selection, OpenHands uses the shared subscription when no personal subscription is connected.

Changing the selected source stops that user's active conversation containers so new requests use the selected credentials. Revoking a grant also stops containers that had the shared credentials mounted.

The shared OAuth file remains in the OpenHands service persistence directory and is never returned through the API. OIDC roles determine administrator access; the browser's session API key cannot elevate an authenticated OIDC user.

## Verify and recover

1. Sign in as an `ai-user`, open **Settings → LLM Profiles**, and connect a personal ChatGPT account.
2. Start a conversation with the native OpenHands agent profile configured for subscription authentication.
3. As an `ai-admin`, copy the user's OIDC account ID into **Shared subscription access** and grant access.
4. As that user, choose a subscription source and start a new conversation.
5. Revoke the grant as an administrator and verify that shared access is no longer available.

If authorization fails, check the selected subscription and confirm that the active profile uses native subscription authentication. Check the `openhands.service` and Agent Server container logs without copying OAuth files or token values. Apply recovery changes with the workflow in [deployment.md](deployment.md).
