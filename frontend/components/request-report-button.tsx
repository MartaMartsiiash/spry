"use client"

import { useState } from "react"
import { toast } from "sonner"

import { Button } from "@/components/ui/button"
import { ApiError, requestWeeklyReport } from "@/lib/api"

/** Receipt for a report that has not been built yet. The id is the order number. */
export function RequestReportButton() {
  const [pending, setPending] = useState(false)

  async function onClick() {
    setPending(true)
    try {
      const accepted = await requestWeeklyReport()
      toast.success(`Report ${accepted.week} is queued (${accepted.id.slice(0, 8)}).`)
    } catch (error) {
      toast.error(error instanceof ApiError ? error.message : "Could not queue the report.")
    } finally {
      setPending(false)
    }
  }

  return (
    <Button type="button" variant="outline" size="sm" onClick={onClick} disabled={pending}>
      {pending ? "Sending…" : "Send me this week's report"}
    </Button>
  )
}
