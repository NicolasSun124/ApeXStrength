# Ape X Strength Manual Testing Procedure

## Purpose

Use this procedure to validate persistence, workout execution, calculations, lifecycle behavior, accessibility, migration, and performance before a release.

Record the app build, device, OS, tester, date, and result for every test. A test passes only when the observed behavior matches every expected result and no crash, data loss, duplicate record, visual defect, or accessibility blocker occurs.

## Test record

| Field | Value |
|---|---|
| Build/version | |
| Git commit | |
| Tester | |
| Date | |
| Physical device(s) | |
| Simulator(s) | |
| iOS version(s) | |
| Upgrade source version | |

Use these result values:

- **Pass** — all expected results occurred.
- **Fail** — at least one expected result did not occur.
- **Blocked** — the test could not be completed; record why.
- **Not run** — intentionally omitted; record why.

For every failure, capture the exact steps, screenshots or video, device logs when relevant, and whether the problem reproduces after relaunch.

## Required coverage

Run the complete procedure on the latest supported iPhone simulator and at least one physical iPhone. Run accessibility checks on both a standard-size and compact-width device. Perform migration tests on a disposable device or simulator that contains data created by the previous production build.

## Baseline test data

Unless a test specifies otherwise, start with a clean installation and create the following data:

1. Create a weighted, repetition-based exercise named **Bench Press** with a 120-second rest target.
2. Create a bodyweight, repetition-based exercise named **Pull-Up** with a 90-second rest target.
3. Create an assisted-weight, repetition-based exercise named **Assisted Pull-Up**.
4. Create a time-based exercise named **Plank**.
5. Create a distance-based exercise named **Run**.
6. Create a workout named **Push Day** containing Bench Press and Pull-Up, in that order.
7. Give Bench Press three planned sets and Pull-Up two planned sets.
8. Add at least two tags to Push Day.
9. Create a second workout named **Conditioning** containing Plank and Run.

## 1. Core Data repository behavior

### 1.1 Create and fetch

1. Create a new exercise with a unique name, muscle, tracking configuration, and rest duration.
2. Leave the screen and reopen the exercise.
3. Create a workout containing the new exercise and save it.
4. Leave the screen and reopen the workout.
5. Force-quit and relaunch the app, then locate both records again.

Expected:

- Every entered field is preserved after navigation and relaunch.
- The exercise appears exactly once in the exercise list.
- The workout appears exactly once in the workout list.
- The workout contains the correct exercises, sets, order, tags, and alternates.

### 1.2 Update and ordering

1. Rename Push Day to **Push Day Updated**.
2. Reorder Pull-Up ahead of Bench Press.
3. Remove one planned Bench Press set.
4. Add an alternate exercise.
5. Save, leave the screen, and reopen the workout.
6. Relaunch the app and inspect it again.

Expected:

- The new name and order persist.
- Planned sets are renumbered consecutively.
- The alternate remains attached to the intended occurrence.
- No unrelated workout or exercise changes.

### 1.3 Archive and restore

1. Archive a workout and an exercise that are not used by an active session.
2. Confirm they disappear from their normal lists.
3. Open the archived lists and restore both.
4. Relaunch the app.

Expected:

- Archived records appear once in the correct archived list.
- Restored records return once to the normal list.
- Relationships and historical sessions remain intact.

## 2. Active-session persistence

1. Start Push Day.
2. Change repetitions and weight in multiple sets.
3. Mark one set complete and leave another incomplete.
4. Wait at least one second for autosave.
5. Navigate away if the UI permits, background the app, then return.
6. Force-quit and relaunch the app.
7. Choose **Resume** when prompted.

Expected:

- The active session is detected after relaunch.
- Its original start time is retained.
- Exercise order, values, added or removed sets, and completion state match the last autosaved state.
- The session is not added to completed history before finishing.
- Elapsed time reflects real elapsed time rather than restarting from zero.

## 3. Draft recovery

### 3.1 Resume

1. Create an active session with partially completed data.
2. Force-quit the app during the session.
3. Relaunch and select **Resume**.

Expected:

- The correct workout name appears in the recovery prompt.
- Resume opens the saved draft without duplicated sets or exercises.
- Completing and saving it creates exactly one history entry.

### 3.2 Discard

1. Create another active draft and relaunch.
2. Select **Discard**.
3. Relaunch once more.

Expected:

- The draft is deleted.
- No recovery prompt appears on the next launch.
- No completed history entry is created.
- The workout template remains available.

## 4. Duplicate-occurrence behavior

If the UI intentionally prevents adding the same exercise twice, verify that prevention first. To validate legacy or migrated duplicates, use a test store containing two occurrences of the same exercise in one session.

1. Open a workout or recovered session containing Bench Press twice.
2. Confirm the occurrences appear in their stored order.
3. Enter different values in each occurrence.
4. Complete and save the workout.
5. Open the history entry.

Expected:

- Both occurrences remain visible and distinct.
- Editing one does not modify the other.
- Each occurrence retains its own sets, completion state, and snapshot data.
- History does not merge, drop, or reorder the occurrences.

## 5. Statistics

1. Complete Push Day once in 30 minutes with 1,000 lb of volume and 50% set completion.
2. Complete it again in 60 minutes with 2,000 lb of volume and 100% completion.
3. Expand the workout's Statistics section.

Expected:

- Last Used equals the second session's completion time.
- Mean Duration is 45 minutes.
- Mean Volume is 1,500 lb.
- Mean Completed is 75%.
- An unfinished or discarded session does not affect statistics.
- A workout with no completed sessions displays placeholders rather than zero or invalid values.

## 6. Improvement comparisons

### 6.1 Weighted exercise

1. Save a Bench Press session at 100 lb for 8 reps.
2. Save another at 100 lb for 10 reps.
3. During a third session, enter 100 lb for 12 reps and open the finish summary.
4. Switch between **Lifetime** and **Previous** comparison.

Expected:

- Max Reps compares 10 to 12 and indicates improvement.
- Max Weight and Volume Weight use the correct current and historical values.
- Lifetime uses all completed history; Previous uses only the latest completed occurrence.

### 6.2 Assisted exercise

1. Save Assisted Pull-Up at 50 lb assistance.
2. Enter the same performance at 40 lb assistance in a new session.

Expected:

- Lower assistance is classified as improvement.
- The metric is labelled **Min Assistance**, not Max Weight.

### 6.3 First entry and regression

1. Finish an exercise that has no history.
2. In a later session, enter performance lower than its comparison value.

Expected:

- The first entry is neutral and does not show a false improvement.
- The lower later result is shown as regression.
- Incomplete sets are excluded from comparisons.

## 7. Unit conversion

1. Set weight units to pounds.
2. Save a completed 220.46 lb set.
3. Change the setting to kilograms and reopen the workout preview and history.
4. Confirm the value is approximately 100 kg.
5. Save a 100 kg set, switch back to pounds, and inspect it again.

Expected:

- Displayed values convert without changing the underlying workout meaning.
- 100 kg displays as approximately 220.46 lb.
- Repeated unit switching does not progressively change stored values.
- Statistics and improvement values use the selected unit and correct suffix.
- Bodyweight exercises do not gain an editable weight field.

Repeat the equivalent display checks for kilometres and miles wherever distance units are shown.

## 8. Rest timer

1. Start a workout and complete a set with a 120-second rest target.
2. Confirm the rest sheet opens and counts down.
3. Add 15 seconds, then remove 15 seconds.
4. Close and reopen the rest sheet from the active-workout control.
5. Background and foreground the app during the countdown.
6. Force-quit, immediately relaunch, and resume the same session.
7. Allow the timer to expire.

Expected:

- The timer starts from the configured duration.
- Adjustments change the deadline exactly once.
- Closing the sheet does not cancel the timer.
- The countdown is based on its absolute end time and remains accurate after backgrounding.
- Relaunch restores only the timer belonging to the resumed session.
- Expired timers are cleared and do not reappear.
- If notifications are enabled and authorized, one completion notification is scheduled.
- Disabling rest notifications prevents notification delivery without breaking the in-app timer.
- Cancelling or finishing the session clears pending timer state and Live Activity state.

## 9. Core Data migration

Perform this test with a backup or disposable installation.

1. Install the previous production version.
2. Create exercises, tags, alternates, multiple workouts, a completed history entry, and an unfinished active draft.
3. Record representative values and take screenshots.
4. Install the candidate build over the existing app without deleting it.
5. Launch the candidate and wait for initial loading to finish.
6. Inspect all recorded objects, resume the draft, and save a new session.
7. Relaunch again.

Expected:

- Launch and automatic migration complete without a crash or reset prompt.
- Existing objects and relationships remain intact and appear exactly once.
- Ordered exercises and sets retain their order.
- Historical snapshot names, muscles, tracking types, and rest values remain readable.
- The pre-upgrade draft resumes successfully.
- New data can be saved and reopened after migration.
- No persistent-store incompatibility or migration error appears in device logs.

## 10. Central workout UI flow

1. Launch into the Workouts tab.
2. Create or open Push Day.
3. Confirm preview content and select **Start**.
4. Edit repetitions and weight.
5. Add and remove a set.
6. Mark a set complete and exercise the rest timer.
7. Add, remove, reorder, or replace an exercise where supported.
8. Select **Finish**.
9. Choose a rating, enter a note, review improvements, and save.
10. Open session history and inspect the saved session.

Expected:

- Every primary action is visible and responds once per activation.
- Keyboard controls do not obscure the edited field or completion actions.
- The finish summary contains the correct workout and improvement data.
- Rating and trimmed note are preserved.
- Exactly one completed history entry is created.
- Returning to the workout list refreshes its last-used date and statistics.

Also repeat the flow using **Don't Save** and confirm that no history entry or statistic is created.

## 11. Accessibility and Dynamic Type

### 11.1 VoiceOver

1. Enable VoiceOver.
2. Navigate the Workouts tab using swipe gestures only.
3. Open a workout, start it, edit a set, mark it complete, and finish it.
4. Exercise custom removal actions for sets where available.

Expected:

- Every interactive control has a meaningful, unique spoken name.
- Current state is announced for selected rating, completed set, timer, and active tab.
- Reading and focus order follow the visual order.
- Icon-only controls identify their action and target.
- Decorative images do not create noise.
- No action requires an unlabeled gesture or precise visual targeting.

### 11.2 Dynamic Type

1. Repeat the central flow at the default text size.
2. Repeat at the largest Accessibility text size.
3. Test portrait and landscape where supported.

Expected:

- Text does not overlap, clip important content, or become illegible.
- Workout names may wrap or truncate safely without hiding identity.
- Start, Finish, Save, navigation, and set-completion actions remain reachable and tappable.
- Scrolling exposes content that no longer fits onscreen.
- Controls retain adequate touch targets.

### 11.3 Additional accessibility settings

Repeat representative screens with Increase Contrast, Reduce Motion, and Bold Text enabled.

Expected:

- State is not communicated by colour alone.
- Text and controls remain distinguishable.
- Reduced motion does not prevent navigation or state updates.

## 12. Backgrounding and interruptions

During an active workout, repeat the following interruptions separately:

1. Press Home and wait 30 seconds before returning.
2. Lock and unlock the device.
3. Open Control Centre and return.
4. Receive a notification and return.
5. Receive and dismiss a phone call on a physical test device, if practical.
6. Trigger low-power mode or a memory-pressure scenario where practical.
7. Force-quit immediately after changing a set, then relaunch.

Expected:

- The app returns to a coherent screen without a blank view or duplicate navigation.
- The active workout and latest autosaved values are recoverable.
- The session start time and timer deadline do not reset.
- No duplicate draft or completed session is created.
- Repeated foreground/background transitions remain stable.

## 13. Time-zone and daylight-saving behavior

Use a disposable simulator so system time settings can be changed safely.

### 13.1 Time-zone change

1. Start a session in America/Toronto.
2. Background the app and change the device time zone to America/Vancouver.
3. Return, finish the session, and inspect history and statistics.

Expected:

- Elapsed duration is based on absolute time and remains correct.
- History displays dates in the current local time zone.
- Session ordering and Last Used remain chronologically correct.

### 13.2 DST boundaries

1. Test stored sessions spanning the spring-forward boundary.
2. Test stored sessions spanning the fall-back boundary.
3. Inspect duration, history order, and displayed dates.

Expected:

- Spring-forward and fall-back sessions use real elapsed time, not naive wall-clock subtraction.
- Repeated local times do not duplicate or reorder sessions.
- Statistics remain unchanged when only the display time zone changes.

## 14. Large-history performance

Use a release-like build with a prepared store containing at least 2,000 completed sessions across multiple workouts and exercises.

1. Cold-launch the app three times.
2. Open the workout list and expand Statistics.
3. Open session history and scroll from newest toward oldest.
4. Search and navigate between workout preview and history repeatedly.
5. Start, autosave, finish, and save a new workout.
6. Monitor memory, hangs, and thermal state with Xcode Instruments when available.

Expected:

- Launch completes without watchdog termination.
- Lists remain responsive and ordered newest-first.
- Scrolling does not show sustained stutter, blank rows, or incorrect reused content.
- Memory does not grow without stabilizing during repeated navigation.
- Statistics and improvement calculations complete without blocking interaction for an unacceptable duration.
- Saving one additional session does not produce duplicates or visibly degrade performance.

Record measured cold-launch time, history-open time, peak memory, and any visible hitching for each device.

## 15. Final regression and release decision

1. Relaunch after all testing.
2. Confirm no unexpected active draft or rest timer remains.
3. Confirm all saved history and templates are still readable.
4. Review every failed or blocked test.

Release criteria:

- No crash, migration failure, data loss, draft loss, or duplicate completed session.
- No incorrect statistics, improvement direction, or unit conversion.
- The central workout flow is completable with touch and VoiceOver.
- Backgrounding, timer recovery, time-zone changes, and large histories do not leave the app unusable.
- Any remaining defect has an explicit severity, owner, and accepted release decision.

## Summary

| Area | Result | Defect/reference | Notes |
|---|---|---|---|
| Core Data repositories | Not run | | |
| Active-session persistence | Not run | | |
| Draft recovery | Not run | | |
| Duplicate occurrences | Not run | | |
| Statistics | Not run | | |
| Improvement comparisons | Not run | | |
| Unit conversion | Not run | | |
| Rest timer | Not run | | |
| Core Data migration | Not run | | |
| Central workout UI | Not run | | |
| Accessibility/Dynamic Type | Not run | | |
| Backgrounding/interruptions | Not run | | |
| Time zone/DST | Not run | | |
| Large-history performance | Not run | | |

**Overall result:** Not run

**Release recommendation:** Undetermined

