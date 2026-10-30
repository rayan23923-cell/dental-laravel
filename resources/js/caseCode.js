// The short, typeable twin of a case's QR (2026-10-30, by request) — a
// supervisor whose camera can't read the code types these digits instead.
// Same algorithm as the server's App\Support\CaseCode, which also turns a
// typed code back into the QR payload: `1` + instance id, or `2` + digit
// count of the task id + task id + doctor id, then a Luhn check digit.

const luhnDigit = (body) => {
    let sum = 0;
    let double = true;
    for (let i = body.length - 1; i >= 0; i--) {
        let d = Number(body[i]);
        if (double) {
            d *= 2;
            if (d > 9) d -= 9;
        }
        sum += d;
        double = !double;
    }
    return (10 - (sum % 10)) % 10;
};

const withCheck = (body) => `${body}${luhnDigit(body)}`;

export const caseCodeForInstance = (instanceId) => withCheck(`1${instanceId}`);

export const caseCodeForPending = (taskId, doctorId) => {
    const task = String(taskId);
    return withCheck(`2${task.length}${task}${doctorId}`);
};

// Groups of three for display, e.g. `145 238`.
export const formatCaseCode = (code) => (code.match(/.{1,3}/g) ?? []).join(' ');
