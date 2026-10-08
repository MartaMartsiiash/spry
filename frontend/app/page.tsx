"use client"

import { useEffect } from "react"

/** The meetings list lives at /today/. Signed-out visitors are sent on to /login/. */
export default function Home() {
  useEffect(() => {
    window.location.replace("/today/")
  }, [])

  return null
}
