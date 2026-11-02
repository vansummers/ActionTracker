# Action Tracker — always-on-desktop to-do widget

A small, frameless, semi-transparent to-do widget for Windows that stays on your
desktop. Add tasks, check them off (they get struck through), delete them, and
clear completed ones. Your list and the window's position are remembered between
runs. Built to be **Themia-like for a to-do list**, but with no account and no sync.

## What it is (and why it's built this way)

- **PowerShell + WPF**, using only components already on every Windows 10/11 PC
  (Windows PowerShell 5.1 + built-in .NET). **Nothing to install, no admin rights.**
- Your data lives only on your machine, at
  `%APPDATA%\ActionTracker\state.json`. Nothing leaves the computer; no network,
  no login.
- This is deliberately the lightest-footprint option so it has the best chance of
  running on a locked-down work computer. See **If it won't run** below.

## How to run it

1. Put the whole `action-tracker` folder somewhere under your user profile, e.g.
   `C:\Users\<you>\ActionTracker\`.
2. Double-click **`Start-ActionTracker.vbs`** (no console flash).
   - `Start-ActionTracker.bat` does the same but flashes a console window briefly.
3. The widget appears top-right. Drag it anywhere by its **"Action Tracker"**
   header. Resize from the bottom-right corner.

## Using it

- **Add a task:** (optional) set a **project** in the box on the left — type a new
  project name, or pick an existing one from its dropdown — then type the action in
  the middle box, optionally pick a **due date** on the right, and press **Enter**.
- **Projects:** each action shows a colour-coded project tag on its left, so you
  can see at a glance which project it belongs to. The project box keeps your last
  choice, so adding several actions to the same project is quick. Projects you've
  already used appear in the dropdown automatically.
- **Due date column:** each task shows its due date. You can change an active
  task's due date right in its row. Overdue active tasks get a red **!**.
- **Complete a task:** click its checkbox. It moves to the **Completed** list for
  review, and its checkbox turns into a green **✓ <date>** stamp showing when it
  was done.
- **Undo a completion (if you clicked it by accident):** switch to the Completed
  view (the **Done (N)** button, top of the widget) and click the green
  **✓ <date>** stamp on that task — it reopens and returns to your active list.
- **Switch views:** the top button toggles between **Active** and **Done (N)**.
- **Delete:** click the **✕** on the right of a task (removes it entirely).
- **Clear completed:** shown only in the Completed view — permanently removes all
  completed tasks once you no longer need them for review.
- **Top:** toggles always-on-top. On = stays above other windows; dim = behaves
  like a normal window so it can sit behind what you're working in.
- **Close (✕ top-right):** closes the widget. Everything (active tasks, completed
  history, due dates, window position) is saved; relaunch any time.

## Start it automatically at login (no admin needed)

1. Press `Win + R`, type `shell:startup`, press Enter. This opens your personal
   Startup folder.
2. Right-click `Start-ActionTracker.vbs` → **Copy**, then paste a **shortcut** to it
   into that Startup folder (right-click → Paste shortcut).

The widget will then launch each time you sign in.

## If it won't run (work-computer constraints)

Because this is a work PC, IT policy — not the widget — decides whether it can run.
Likely messages and what they mean:

- **"running scripts is disabled on this system"** — the launchers already pass
  `-ExecutionPolicy Bypass`, which is per-process and needs no admin, so this
  usually won't appear. If it does, your machine is under a stricter machine-level
  policy.
- **"This program is blocked by group policy" / AppLocker / Constrained Language
  Mode** — IT has locked down script and app execution. In that case no
  self-contained widget (this one, Themia, or anything else) can run without IT
  allowing it. That's a policy wall, not something code can get around.

If you hit one of those, tell me the exact message and I'll confirm whether
there's a permitted path or whether it genuinely needs IT.

## Not included (yet)

- Microsoft 365 sync (your Outlook tasks/To Do, calendar, mail). That needs your
  IT team to allow the connection and is a separate piece of work — this widget is
  the standalone, always-visible tracker you wanted first.
