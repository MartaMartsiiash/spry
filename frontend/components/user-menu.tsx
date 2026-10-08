"use client"

import { LogOut } from "lucide-react"
import Link from "next/link"

import { useAuth } from "@/components/auth-provider"
import { Button } from "@/components/ui/button"

/** Email stays in the header itself: the lab screenshot has to show it. */
export function UserMenu() {
  const { status, user, signOut } = useAuth()

  if (status === "loading") return null

  if (status !== "signedIn" || !user) {
    return (
      <Button asChild size="sm">
        <Link href="/login/">Sign in</Link>
      </Button>
    )
  }

  const email = user.email ?? user.name ?? "Signed in"

  return (
    <div className="flex items-center gap-2">
      <span className="max-w-40 truncate text-sm sm:max-w-56">{email}</span>
      <Button variant="outline" size="sm" onClick={() => void signOut()}>
        <LogOut className="size-4" aria-hidden />
        Sign out
      </Button>
    </div>
  )
}
