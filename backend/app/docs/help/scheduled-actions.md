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
conversation and you get a notification. The card shows the next run time.

## How do I pause or delete one?
Each action's card has a switch to pause/resume it without losing the
schedule, and a delete button to remove it entirely. To change the prompt
or schedule, delete it and create a new one.
