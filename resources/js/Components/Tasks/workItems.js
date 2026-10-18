/**
 * Stored work items keep labels; maps them back to a task's option,
 * multiplier and checklist indexes for WorkItemsInput (2026-10-14). A
 * graded task lists every item once; a plain one starts with one row.
 * Shared by the task-progress dialogs and the case sheets' points panel.
 */
export function workItemsToForm(scoring, workItems) {
    const s = scoring ?? {};
    const items = (workItems ?? [])
        .map((w) =>
            w.check
                ? { check: (s.checklist ?? []).findIndex((c) => c.label === w.option), grade: w.grade ?? null }
                : {
                      option: (s.options ?? []).findIndex((o) => o.label === w.option),
                      qty: w.qty ?? 1,
                      grade: w.grade ?? null,
                      modifiers: (w.modifiers ?? []).map((m) => (s.modifiers ?? []).findIndex((x) => x.label === m)).filter((i) => i >= 0),
                  },
        )
        .filter((w) => (w.check ?? w.option) >= 0);
    if (s.graded) {
        (s.options ?? []).forEach((o, i) => {
            if (o.enabled !== false && !items.some((w) => w.option === i)) items.push({ option: i, qty: 1, grade: null, modifiers: [] });
        });
        items.sort((a, b) => (a.option ?? -1) - (b.option ?? -1));
    } else if (s.options?.length && !items.some((w) => w.check === undefined)) {
        items.push({ option: Math.max(0, s.options.findIndex((o) => o.enabled !== false)), qty: 1, modifiers: [] });
    }
    return items;
}

/** Whether a task has work to record on a case (kinds of work or a checklist). */
export const hasWork = (scoring) => !!scoring?.options?.length || !!scoring?.checklist?.length;

/** A task's steps to sign, as App\Support\TaskSteps lists them, for a case not started yet (2026-10-18). */
export function stepsFromScoring(scoring) {
    const off = !!scoring?.points_off;
    return [
        ...(scoring?.steps ?? []).filter((s) => s.enabled !== false).map((s) => ({ key: `s:${s.key}`, label: s.label, max: off ? null : Number(s.max) })),
        ...(scoring?.checklist ?? []).map((c, i) => ({ key: `c:${i}`, label: c.label, max: !off && c.scored ? Number(c.max) : null })),
    ];
}
