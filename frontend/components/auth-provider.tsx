"use client"

import { useQueryClient } from "@tanstack/react-query"
import { AuthProvider as OidcAuthProvider, useAuth as useOidcAuth } from "react-oidc-context"
import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useSyncExternalStore } from "react"

import { syncMe } from "@/lib/api"
import {
  cognitoLogoutUrl,
  getUserManager,
  isAuthConfigured,
} from "@/lib/auth"

export type AuthUser = {
  sub: string
  email?: string
  name?: string
}

type AuthState =
  | { status: "loading"; user: null }
  | { status: "signedOut"; user: null }
  | { status: "signedIn"; user: AuthUser }

type AuthContextValue = AuthState & {
  error: string | null
  signIn: () => Promise<void>
  signOut: () => Promise<void>
}

const AuthContext = createContext<AuthContextValue | null>(null)

const loadingValue: AuthContextValue = {
  status: "loading",
  user: null,
  error: null,
  signIn: async () => {},
  signOut: async () => {},
}

function profileOf(user: { profile: Record<string, unknown>; id_token?: string }): {
  authUser: AuthUser
  idToken?: string
} | null {
  const sub = user.profile.sub
  if (typeof sub !== "string" || !sub) return null
  const email = user.profile.email
  const name = user.profile.name
  return {
    idToken: user.id_token,
    authUser: {
      sub,
      email: typeof email === "string" ? email : undefined,
      name: typeof name === "string" ? name : undefined,
    },
  }
}

/** Bridges react-oidc-context into the shape the rest of the app already uses. */
function OidcBridge({ children }: { children: React.ReactNode }) {
  const oidc = useOidcAuth()
  const queryClient = useQueryClient()
  const syncedSub = useRef<string | null>(null)

  const idToken = oidc.user?.id_token
  const sub = typeof oidc.user?.profile.sub === "string" ? oidc.user.profile.sub : undefined

  useEffect(() => {
    if (!idToken || !sub || syncedSub.current === sub) return
    syncedSub.current = sub
    syncMe(idToken).catch((error) => console.warn("Profile sync failed", error))
  }, [idToken, sub])

  const signIn = useCallback(() => oidc.signinRedirect(), [oidc])

  const signOut = useCallback(async () => {
    queryClient.clear()
    syncedSub.current = null
    await oidc.removeUser()
    window.location.assign(cognitoLogoutUrl())
  }, [oidc, queryClient])

  const value = useMemo<AuthContextValue>(() => {
    const error = oidc.error?.message ?? null
    if (oidc.isLoading) return { status: "loading", user: null, error, signIn, signOut }
    const profile = oidc.user ? profileOf(oidc.user) : null
    if (oidc.isAuthenticated && profile) {
      return { status: "signedIn", user: profile.authUser, error, signIn, signOut }
    }
    return { status: "signedOut", user: null, error, signIn, signOut }
  }, [oidc.error, oidc.isAuthenticated, oidc.isLoading, oidc.user, signIn, signOut])

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>
}

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const configured = isAuthConfigured()
  // The UserManager needs window. The server snapshot is null; the client one
  // is the single cached manager, so this does not re-render in a loop.
  const manager = useSyncExternalStore(
    () => () => {},
    () => (configured ? getUserManager() : null),
    () => null,
  )

  const unconfigured = useMemo<AuthContextValue>(
    () => ({
      status: "signedOut",
      user: null,
      error: null,
      signIn: async () => {
        throw new Error("Sign-in is not configured.")
      },
      signOut: async () => {},
    }),
    [],
  )

  if (!configured) {
    return <AuthContext.Provider value={unconfigured}>{children}</AuthContext.Provider>
  }

  if (!manager) {
    return <AuthContext.Provider value={loadingValue}>{children}</AuthContext.Provider>
  }

  return (
    <OidcAuthProvider
      userManager={manager}
      onSigninCallback={() => {
        window.location.replace("/today/")
      }}
    >
      <OidcBridge>{children}</OidcBridge>
    </OidcAuthProvider>
  )
}

export function useAuth() {
  const context = useContext(AuthContext)
  if (!context) throw new Error("useAuth must be used inside <AuthProvider>")
  return context
}
