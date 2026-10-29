"use client"

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query"

import {
  createMeeting,
  deleteMeeting,
  listMeetings,
  saveMeetingAgenda,
  updateMeeting,
} from "@/lib/api"
import type { AiSuggestion, MeetingCreateInput, ParsedAgenda } from "@/lib/types"

/** Shared cache key: the list and the header menu read the same entry. */
export const meetingsKey = (date?: string) => ["meetings", { date: date ?? "today" }] as const

export function useMeetings(date?: string) {
  return useQuery({
    queryKey: meetingsKey(date),
    queryFn: () => listMeetings({ date }),
  })
}

export function useCreateMeeting() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (payload: MeetingCreateInput) => createMeeting(payload),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ["meetings"] }),
  })
}

export function useUpdateMeeting() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: ({ id, payload }: { id: string; payload: MeetingCreateInput }) =>
      updateMeeting(id, payload),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ["meetings"] }),
  })
}

export function useDeleteMeeting() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (id: string) => deleteMeeting(id),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ["meetings"] }),
  })
}

export function useSaveMeetingAgenda() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: ({
      id,
      agenda,
      ai_suggestion,
    }: {
      id: string
      agenda: ParsedAgenda
      ai_suggestion?: AiSuggestion | null
    }) => saveMeetingAgenda(id, { agenda, ai_suggestion }),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ["meetings"] }),
  })
}
