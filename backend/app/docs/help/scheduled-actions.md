# Scheduled Actions

Have the assistant do something for you later, once or on a schedule — e.g.
a daily summary of your notifications every morning, or a weekly reminder.

## How do I create one?
Open the **Scheduled actions** page and press **New scheduled action**.
Write the prompt ("What should the assistant do?"), optionally a title, and
pick when it runs:
- **One-off** — a single date and time (**Run at**)
- **Recurring** — a cron expression (`min hour day month weekday`, e.g.
  `0 9 * * mon-fri` for weekday mornings)

## What happens when it runs?
The assistant executes your prompt in the background; the result lands in a
conversation and you get a notification. Actions without an explicitly chosen
model use GLM 5.2 by default. The card shows the next run time.

## How do I pause, edit, or delete one?
Each action's card has a switch to pause/resume it without losing the
schedule, an edit (pencil) button that reopens the form pre-filled — you
can change the title, prompt, and schedule, including switching between
recurring and one-off — and a delete button to remove it entirely.
