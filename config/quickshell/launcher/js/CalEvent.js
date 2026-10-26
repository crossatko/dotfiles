.pragma library

// "Add event" helpers for the calendar popup (CalAddEvent.qml / CalCreate.qml): input validation and the
// `omacal events create` argv. Pure functions, no processes. User text only ever travels as its own argv element.

var TIME = /^([01]?\d|2[0-3]):([0-5]\d)$/;

function pad(n) { return n < 10 ? "0" + n : "" + n; }

// "9:5" / "09:05" -> minutes since midnight, or -1 when it is not an HH:MM time
function minutes(s) {
    var m = TIME.exec((s || "").trim());
    return m ? parseInt(m[1], 10) * 60 + parseInt(m[2], 10) : -1;
}
function hhmm(min) { return pad(Math.floor(min / 60)) + ":" + pad(min % 60); }

// default start: the next full hour when `day` is today (else 09:00), clamped so start+1h stays on the same day
function defaultStart(day, now) {
    var same = day.getFullYear() === now.getFullYear() && day.getMonth() === now.getMonth() && day.getDate() === now.getDate();
    if (!same) return "09:00";
    var h = now.getHours() + 1;
    return hhmm(Math.min(h, 22) * 60);
}
function plusHour(start) {
    var m = minutes(start);
    return m < 0 ? "" : hhmm(Math.min(m + 60, 23 * 60 + 59));
}

// "YYYY-MM-DD" (a real calendar date) -> true
function validDate(s) {
    var m = /^(\d{4})-(\d{2})-(\d{2})$/.exec((s || "").trim());
    if (!m) return false;
    var d = new Date(+m[1], +m[2] - 1, +m[3]);
    return d.getFullYear() === +m[1] && d.getMonth() === +m[2] - 1 && d.getDate() === +m[3];
}
function isoDate(d) { return d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate()); }
// date string shifted by n days (unchanged when invalid)
function shiftDate(s, n) {
    if (!validDate(s)) return s;
    var p = s.trim().split("-");
    return isoDate(new Date(+p[0], +p[1] - 1, +p[2] + n));
}
// days from `date` to `endDate` counted inclusively ("2026-10-26", "2026-10-28" -> 3); 0 when either is invalid
function spanDays(date, endDate) {
    if (!validDate(date) || !validDate(endDate)) return 0;
    var a = date.trim().split("-"), b = endDate.trim().split("-");
    // UTC days: a DST change in between must not shorten the span
    return Math.round((Date.UTC(+b[0], +b[1] - 1, +b[2]) - Date.UTC(+a[0], +a[1] - 1, +a[2])) / 86400000) + 1;
}

// error text, or "" when the input is fine. date/endDate: YYYY-MM-DD (endDate inclusive; empty = same day)
function validate(title, start, end, allDay, date, endDate) {
    if ((title || "").trim() === "") return "Give the event a title";
    var ed = (endDate || "").trim() || date;
    if (date !== undefined) {
        if (!validDate(ed)) return "Date must look like 2026-10-27";
        if (ed < date) return "Ends before it starts";
    }
    if (allDay) return "";
    var s = minutes(start), e = minutes(end);
    if (s < 0 || e < 0) return "Times must look like 09:30";
    if (ed === date && e <= s) return "End must be after the start";
    return "";
}

// argv for `omacal events create`; `bin` is the omacal executable, `date`/`endDate` are YYYY-MM-DD (endDate is
// the last day, inclusive; empty = same day). All day: --date + --last-day (inclusive); timed multi-day: --end-date.
// calendarId: numeric omacal calendar id (omitted = the app's own default calendar).
function createArgs(bin, title, date, start, end, allDay, endDate, calendarId) {
    var ed = (endDate || "").trim() || date;
    var a = [bin, "events", "create", "--title", title.trim(), "--date", date];
    if (allDay) a.push("--all-day", "--last-day", ed);
    else {
        a.push("--start", hhmm(minutes(start)));
        if (ed !== date) a.push("--end-date", ed);
        a.push("--end", hhmm(minutes(end)));
    }
    if (calendarId !== undefined && calendarId !== null && calendarId !== "" && calendarId >= 0) a.push("--calendar", String(calendarId));
    a.push("--json");
    return a;
}

// stdout JSON of `omacal ... --json` -> { ok, message }
function parseResult(text, exitCode) {
    try {
        var d = JSON.parse(text);
        if (d.ok) return { ok: true, message: "" };
        return { ok: false, message: (d.error && d.error.message) || "omacal refused the event" };
    } catch (e) {
        return { ok: false, message: "omacal failed (exit " + exitCode + ")" };
    }
}

// index into `calendars` ([{id,...}]) to preselect: the last used id if it is still there, else the primary, else the first
function pickCalendar(calendars, lastId) {
    var i, n = calendars ? calendars.length : 0;
    for (i = 0; i < n; i++) if (calendars[i].id === lastId) return i;
    for (i = 0; i < n; i++) if (calendars[i].primary) return i;
    return n > 0 ? 0 : -1;
}
