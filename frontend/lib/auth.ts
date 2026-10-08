import { UserManager, WebStorageStateStore } from "oidc-client-ts"

/**
 * Cognito settings baked in at build time (see the frontend Dockerfile).
 * Locally, docker compose passes the same names. The pool id + region are a
 * fallback when COGNITO_ISSUER was not pasted into .env yet.
 */
export function cognitoAuthority(): string {
  const configured = process.env.NEXT_PUBLIC_COGNITO_AUTHORITY ?? ""
  if (configured) return configured
  const poolId = process.env.NEXT_PUBLIC_COGNITO_USER_POOL_ID ?? ""
  const region = process.env.NEXT_PUBLIC_COGNITO_REGION ?? ""
  if (!poolId || !region) return ""
  return `https://cognito-idp.${region}.amazonaws.com/${poolId}`
}

export const cognitoClientId = process.env.NEXT_PUBLIC_COGNITO_CLIENT_ID ?? ""
export const cognitoDomain = process.env.NEXT_PUBLIC_COGNITO_DOMAIN ?? ""

export function isAuthConfigured(): boolean {
  return Boolean(cognitoAuthority() && cognitoClientId && cognitoDomain)
}

/** Must match a CallbackURL on the app client, including the trailing slash. */
export function redirectUri(): string {
  const configured = process.env.NEXT_PUBLIC_COGNITO_REDIRECT_URI ?? ""
  if (configured) return configured
  return `${window.location.origin}/auth/callback/`
}

/** Must match a LogoutURL on the app client, including the trailing slash. */
export function logoutUri(): string {
  const configured = process.env.NEXT_PUBLIC_COGNITO_LOGOUT_URI ?? ""
  if (configured) return configured
  return `${window.location.origin}/`
}

let manager: UserManager | null = null

/** One UserManager for the tab. oidc-client-ts keeps the PKCE verifier here. */
export function getUserManager(): UserManager {
  if (manager) return manager
  manager = new UserManager({
    authority: cognitoAuthority(),
    client_id: cognitoClientId,
    redirect_uri: redirectUri(),
    response_type: "code",
    scope: "openid email profile",
    // Email is in the ID token. Cognito's userinfo call is unnecessary.
    loadUserInfo: false,
    automaticSilentRenew: true,
    userStore: new WebStorageStateStore({ store: window.sessionStorage }),
  })
  return manager
}

/** Access token for the API. The ID token stays in the browser for the header. */
export async function getAccessToken(): Promise<string | null> {
  if (!manager) return null
  const user = await manager.getUser()
  if (!user) return null
  if (!user.expired) return user.access_token
  try {
    const renewed = await manager.signinSilent()
    return renewed?.access_token ?? null
  } catch {
    return null
  }
}

export async function clearLocalSession(): Promise<void> {
  if (!manager) return
  await manager.removeUser()
}

/**
 * Cognito has no OIDC end-session endpoint. Drop the local session, then
 * send the browser to the pool's logout URL.
 */
export function cognitoLogoutUrl(): string {
  const params = new URLSearchParams({
    client_id: cognitoClientId,
    logout_uri: logoutUri(),
  })
  return `https://${cognitoDomain}/logout?${params.toString()}`
}
