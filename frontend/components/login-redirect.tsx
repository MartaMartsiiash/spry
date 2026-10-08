"use client"

import { useEffect, useRef } from "react"

import { AuthLoading } from "@/components/require-auth"
import { useAuth } from "@/components/auth-provider"
import { isAuthConfigured } from "@/lib/auth"

/**
 * The URL submitted for the lab. The library stores a random state and a PKCE
 * verifier, then Cognito's managed login shows email/password and Google.
 * Opening a Cognito URL by hand skips that state, and the callback is rejected.
 */
let redirectStarted = false

export function LoginRedirect() {
  const { status, signIn, error } = useAuth()
  const started = useRef(false)

  useEffect(() => {
    if (status === "signedIn") {
      window.location.replace("/today/")
      return
    }
    if (!isAuthConfigured() || status !== "signedOut" || started.current || redirectStarted) return
    started.current = true
    redirectStarted = true
    void signIn()
  }, [signIn, status])

  if (error) {
    return (
      <p role="alert" className="text-destructive px-6 py-24 text-center text-sm">
        {error}
      </p>
    )
  }

  if (!isAuthConfigured()) {
    return (
      <p className="text-muted-foreground px-6 py-24 text-center text-sm">
        Sign-in is not configured. Deploy the auth stack and rebuild the site.
      </p>
    )
  }

  return <AuthLoading label="Redirecting to sign in…" />
}
