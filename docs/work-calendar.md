# Home Assistant work calendar

Task branch: `feat/work-calendar`, based on Flutter `f9b7ebf`, HA integration
`73f5a3a`, and VPS backend `fde81a0`. Each repository keeps its own commit.

The CTR integration's Home Assistant options accept one optional calendar entity
for the connected household. Every event counts, regardless of its title. HA sends
only occupied dates through the existing authenticated CTR WebSocket; event
contents and calendar credentials stay in HA. All-day dates retain their meaning;
timed events use HA's configured local timezone. Event ends are exclusive, so an
event ending at midnight does not mark the next day. Overlapping events produce
one bar per date.

HA subscribes to calendar event updates and entity state changes, with a 60-second
poll as a fallback and retry after failures. The source calendar's own refresh
schedule still controls how soon HA sees an external change. Each successful
refresh replaces the date list, so moved/deleted events remove previous markers.
An unavailable calendar retains the last successful dates; clearing the calendar
selection publishes an empty date list. The rolling sync window covers 366 days
before today through 730 days after today; dates outside it have no markers.

Settings has a household Workday color palette (amber by default). The meal planner
shows only a slim color bar beside marked dates, including dates without meals.
There is no planner label or tooltip. Color changes use the existing local-first
outbox; dates/color arrive in household snapshots and remain available offline.
HA date updates preserve the household color, and color edits preserve dates.

Backend setup requires the explicit one-time `bin/work-calendar.sql` schema step
before deploying the changed backend. Then install the changed HA integration and
select its calendar. App installation requires a separately requested build or
release. Source implementation does not install or deploy these changes.

Validation: affected Dart files formatted; affected sources and new tests analyzed
without issues. Three new Flutter tests cover markers and incoming changes,
settings color selection, and offline restart/delivery/account separation. All 37 existing
planner and access regressions passed in a separate serial run. No app build or full suite was requested.
