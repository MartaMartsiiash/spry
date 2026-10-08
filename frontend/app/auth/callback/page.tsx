"use client"

import { useAuth } from "@/components/auth-provider"
import { AuthLoading } from "@/components/require-auth"

/** Cognito returns the authorization code here. The provider exchanges it. */
export default function AuthCallbackPage() {
  const { error, status } = useAuth()

  if (error && status !== "signedIn") {
    return (
      <p role="alert" className="text-destructive px-6 py-24 text-center text-sm">
        {error}
      </p>
    )
  }

  return <AuthLoading label="Signing you in…" />
}