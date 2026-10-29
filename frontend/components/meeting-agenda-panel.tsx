"use client"

import { Loader2, Sparkles, X } from "lucide-react"
import { useEffect, useMemo, useRef, useState } from "react"
import { toast } from "sonner"

import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { ApiError, parseAgendaText, saveMeetingAgenda } from "@/lib/api"
import type { ActionItem, AgendaItem, Meeting, ParsedAgenda } from "@/lib/types"

type FieldKey =
  | "title"
  | "starts_at"
  | "duration_minutes"
  | "language"
  | `item:${number}:topic`
  | `item:${number}:owner`
  | `item:${number}:minutes`
  | `action:${number}:task`
  | `action:${number}:owner`
  | `action:${number}:due`

function emptyAgenda(): ParsedAgenda {
  return {
    title: null,
    starts_at: null,
    duration_minutes: null,
    items: [{ topic: "", owner: null, minutes: null }],
    action_items: [],
    language: "uk",
  }
}

function Suggested({ show }: { show: boolean }) {
  if (!show) return null
  return (
    <Badge variant="secondary" className="ml-2 text-[10px] font-normal tracking-wide uppercase">
      suggested
    </Badge>
  )
}

export function MeetingAgendaPanel({
  meeting,
  onSaved,
}: {
  meeting: Meeting
  onSaved: (meeting: Meeting) => void
}) {
  const [paste, setPaste] = useState("")
  const [parsing, setParsing] = useState(false)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [agenda, setAgenda] = useState<ParsedAgenda>(meeting.agenda ?? emptyAgenda())
  const [suggestionMeta, setSuggestionMeta] = useState<{
    agenda: ParsedAgenda
    model: string
    prompt_version: string
  } | null>(meeting.ai_suggestion)
  const [touched, setTouched] = useState<Set<FieldKey>>(new Set())
  const abortRef = useRef<AbortController | null>(null)

  useEffect(() => {
    setAgenda(meeting.agenda ?? emptyAgenda())
    setSuggestionMeta(meeting.ai_suggestion)
    setTouched(new Set())
    setPaste("")
    setError(null)
  }, [meeting.id, meeting.agenda, meeting.ai_suggestion])

  const tz = useMemo(() => Intl.DateTimeFormat().resolvedOptions().timeZone || "Europe/Kyiv", [])
  const today = useMemo(() => {
    const d = new Date()
    const y = d.getFullYear()
    const m = String(d.getMonth() + 1).padStart(2, "0")
    const day = String(d.getDate()).padStart(2, "0")
    return `${y}-${m}-${day}`
  }, [])

  function markTouched(key: FieldKey) {
    setTouched((prev) => new Set(prev).add(key))
  }

  function isSuggested(key: FieldKey): boolean {
    if (!suggestionMeta) return false
    if (touched.has(key)) return false
    const s = suggestionMeta.agenda
    switch (key) {
      case "title":
        return Boolean(s.title)
      case "starts_at":
        return Boolean(s.starts_at)
      case "duration_minutes":
        return s.duration_minutes != null
      case "language":
        return Boolean(s.language)
      default:
        if (key.startsWith("item:")) {
          const [, index, field] = key.split(":")
          const item = s.items[Number(index)]
          if (!item) return false
          const value = item[field as keyof AgendaItem]
          return value != null && value !== ""
        }
        if (key.startsWith("action:")) {
          const [, index, field] = key.split(":")
          const item = s.action_items[Number(index)]
          if (!item) return false
          const value = item[field as keyof ActionItem]
          return value != null && value !== ""
        }
        return false
    }
  }

  async function onParse() {
    setError(null)
    abortRef.current?.abort()
    const controller = new AbortController()
    abortRef.current = controller
    setParsing(true)
    try {
      const result = await parseAgendaText(paste, today, tz, controller.signal)
      setAgenda({
        ...result.agenda,
        items:
          result.agenda.items.length > 0
            ? result.agenda.items
            : [{ topic: "", owner: null, minutes: null }],
      })
      setSuggestionMeta({
        agenda: result.agenda,
        model: result.model,
        prompt_version: result.prompt_version,
      })
      setTouched(new Set())
      toast.success("Agenda parsed — check the fields before saving.")
    } catch (err) {
      if (err instanceof ApiError && err.code === "aborted") return
      const message =
        err instanceof ApiError
          ? err.code === "payload_too_large"
            ? "The text is too long (max 10,000 characters)."
            : err.code === "throttled"
              ? "The service is busy. Try again in a moment, or type the agenda by hand."
              : err.code === "parse_failed"
                ? "The model could not find an agenda in that text."
                : err.message
          : "Parsing failed."
      setError(message)
    } finally {
      setParsing(false)
    }
  }

  function cancelParse() {
    abortRef.current?.abort()
    setParsing(false)
  }

  function updateItem(index: number, patch: Partial<AgendaItem>) {
    setAgenda((prev) => ({
      ...prev,
      items: prev.items.map((item, i) => (i === index ? { ...item, ...patch } : item)),
    }))
  }

  function updateAction(index: number, patch: Partial<ActionItem>) {
    setAgenda((prev) => ({
      ...prev,
      action_items: prev.action_items.map((item, i) =>
        i === index ? { ...item, ...patch } : item,
      ),
    }))
  }

  async function onSave() {
    setSaving(true)
    setError(null)
    try {
      const cleaned: ParsedAgenda = {
        ...agenda,
        title: agenda.title?.trim() || null,
        starts_at: agenda.starts_at?.trim() || null,
        items: agenda.items
          .map((item) => ({
            topic: item.topic.trim(),
            owner: item.owner?.trim() || null,
            minutes: item.minutes,
          }))
          .filter((item) => item.topic.length > 0),
        action_items: agenda.action_items
          .map((item) => ({
            task: item.task.trim(),
            owner: item.owner?.trim() || null,
            due: item.due?.trim() || null,
          }))
          .filter((item) => item.task.length > 0),
        language: agenda.language.trim() || "uk",
      }
      if (cleaned.items.length === 0) {
        setError("Add at least one agenda topic before saving.")
        return
      }
      const saved = await saveMeetingAgenda(meeting.id, {
        agenda: cleaned,
        ai_suggestion: suggestionMeta,
      })
      onSaved(saved)
      toast.success("Agenda saved.")
    } catch (err) {
      setError(err instanceof ApiError ? err.message : "Could not save the agenda.")
    } finally {
      setSaving(false)
    }
  }

  return (
    <section className="space-y-4 rounded-lg border p-4">
      <header className="space-y-1">
        <h3 className="flex items-center gap-2 text-sm font-semibold">
          <Sparkles className="size-4" aria-hidden />
          Paste an agenda
        </h3>
        <p className="text-muted-foreground text-xs">
          Paste an email or notes. The model suggests fields; you check them and save.
        </p>
      </header>

      <div className="space-y-2">
        <Label htmlFor={`paste-${meeting.id}`}>Pasted text</Label>
        <Textarea
          id={`paste-${meeting.id}`}
          value={paste}
          onChange={(e) => setPaste(e.target.value)}
          rows={5}
          placeholder="Пн 10:00, синк по прайсингу…"
          disabled={parsing}
        />
        <div className="flex flex-wrap gap-2">
          <Button type="button" onClick={onParse} disabled={parsing || !paste.trim()}>
            {parsing ? <Loader2 className="animate-spin" aria-hidden /> : null}
            Parse
          </Button>
          {parsing ? (
            <Button type="button" variant="outline" onClick={cancelParse}>
              <X aria-hidden />
              Cancel
            </Button>
          ) : null}
        </div>
        {parsing ? (
          <p className="text-muted-foreground text-xs" role="status">
            Parsing with Claude… usually 2–8 seconds.
          </p>
        ) : null}
      </div>

      {error ? (
        <p className="text-destructive text-sm" role="alert">
          {error}
        </p>
      ) : null}

      <div className="space-y-3 border-t pt-4">
        <h4 className="text-sm font-semibold">Agenda form</h4>

        <div className="grid gap-3 sm:grid-cols-2">
          <div className="space-y-1.5 sm:col-span-2">
            <Label className="inline-flex items-center">
              Title
              <Suggested show={isSuggested("title")} />
            </Label>
            <Input
              value={agenda.title ?? ""}
              onChange={(e) => {
                markTouched("title")
                setAgenda((a) => ({ ...a, title: e.target.value || null }))
              }}
            />
          </div>
          <div className="space-y-1.5">
            <Label className="inline-flex items-center">
              Starts at
              <Suggested show={isSuggested("starts_at")} />
            </Label>
            <Input
              value={agenda.starts_at ?? ""}
              placeholder="2026-10-27T10:00:00+03:00"
              onChange={(e) => {
                markTouched("starts_at")
                setAgenda((a) => ({ ...a, starts_at: e.target.value || null }))
              }}
            />
          </div>
          <div className="space-y-1.5">
            <Label className="inline-flex items-center">
              Duration (minutes)
              <Suggested show={isSuggested("duration_minutes")} />
            </Label>
            <Input
              type="number"
              min={1}
              max={600}
              value={agenda.duration_minutes ?? ""}
              onChange={(e) => {
                markTouched("duration_minutes")
                const v = e.target.value
                setAgenda((a) => ({
                  ...a,
                  duration_minutes: v === "" ? null : Number(v),
                }))
              }}
            />
          </div>
        </div>

        <div className="space-y-2">
          <div className="flex items-center justify-between">
            <Label>Items</Label>
            <Button
              type="button"
              variant="outline"
              size="sm"
              onClick={() =>
                setAgenda((a) => ({
                  ...a,
                  items: [...a.items, { topic: "", owner: null, minutes: null }],
                }))
              }
            >
              Add item
            </Button>
          </div>
          {agenda.items.map((item, index) => (
            <div key={index} className="grid gap-2 rounded-md border p-3 sm:grid-cols-6">
              <div className="space-y-1 sm:col-span-3">
                <Label className="inline-flex items-center text-xs">
                  Topic
                  <Suggested show={isSuggested(`item:${index}:topic`)} />
                </Label>
                <Input
                  value={item.topic}
                  onChange={(e) => {
                    markTouched(`item:${index}:topic`)
                    updateItem(index, { topic: e.target.value })
                  }}
                />
              </div>
              <div className="space-y-1 sm:col-span-2">
                <Label className="inline-flex items-center text-xs">
                  Owner
                  <Suggested show={isSuggested(`item:${index}:owner`)} />
                </Label>
                <Input
                  value={item.owner ?? ""}
                  onChange={(e) => {
                    markTouched(`item:${index}:owner`)
                    updateItem(index, { owner: e.target.value || null })
                  }}
                />
              </div>
              <div className="space-y-1">
                <Label className="inline-flex items-center text-xs">
                  Min
                  <Suggested show={isSuggested(`item:${index}:minutes`)} />
                </Label>
                <Input
                  type="number"
                  min={1}
                  max={480}
                  value={item.minutes ?? ""}
                  onChange={(e) => {
                    markTouched(`item:${index}:minutes`)
                    const v = e.target.value
                    updateItem(index, { minutes: v === "" ? null : Number(v) })
                  }}
                />
              </div>
            </div>
          ))}
        </div>

        <div className="space-y-2">
          <div className="flex items-center justify-between">
            <Label>Action items</Label>
            <Button
              type="button"
              variant="outline"
              size="sm"
              onClick={() =>
                setAgenda((a) => ({
                  ...a,
                  action_items: [
                    ...a.action_items,
                    { task: "", owner: null, due: null },
                  ],
                }))
              }
            >
              Add action
            </Button>
          </div>
          {agenda.action_items.map((item, index) => (
            <div key={index} className="grid gap-2 rounded-md border p-3 sm:grid-cols-3">
              <div className="space-y-1">
                <Label className="inline-flex items-center text-xs">
                  Task
                  <Suggested show={isSuggested(`action:${index}:task`)} />
                </Label>
                <Input
                  value={item.task}
                  onChange={(e) => {
                    markTouched(`action:${index}:task`)
                    updateAction(index, { task: e.target.value })
                  }}
                />
              </div>
              <div className="space-y-1">
                <Label className="inline-flex items-center text-xs">
                  Owner
                  <Suggested show={isSuggested(`action:${index}:owner`)} />
                </Label>
                <Input
                  value={item.owner ?? ""}
                  onChange={(e) => {
                    markTouched(`action:${index}:owner`)
                    updateAction(index, { owner: e.target.value || null })
                  }}
                />
              </div>
              <div className="space-y-1">
                <Label className="inline-flex items-center text-xs">
                  Due
                  <Suggested show={isSuggested(`action:${index}:due`)} />
                </Label>
                <Input
                  type="date"
                  value={item.due ?? ""}
                  onChange={(e) => {
                    markTouched(`action:${index}:due`)
                    updateAction(index, { due: e.target.value || null })
                  }}
                />
              </div>
            </div>
          ))}
        </div>

        {suggestionMeta ? (
          <p className="text-muted-foreground text-xs">
            Suggestion from {suggestionMeta.model} ({suggestionMeta.prompt_version}). Corrections
            you make are stored next to it on Save.
          </p>
        ) : null}

        <Button type="button" onClick={onSave} disabled={saving || parsing}>
          {saving ? <Loader2 className="animate-spin" aria-hidden /> : null}
          Save agenda
        </Button>
      </div>
    </section>
  )
}
