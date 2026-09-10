# TimezoneScribe: unchecked `java.time.DateTimeException` escapes `Ezvcard.parse()`

**Found by:** `fuzz-vcard` (Jazzer), ~6 000 execs from the committed seeds (`rfc6350-example.vcf` carries
`TZ:-0500`; the mutation `TZ:-2039` triggers it). Reproduces in every vCard version (2.1, 3.0, 4.0).

**Reproduce**

    /mayhem/fuzz-vcard-standalone mayhem/fuzz-vcard/known-findings/timezone-scribe-datetimeexception/minimal-tz-offset-out-of-range.vcf

or, from the API, `Ezvcard.parse("BEGIN:VCARD\r\nVERSION:4.0\r\nTZ:-2039\r\nEND:VCARD\r\n").first()`.

    == Java Exception: java.time.DateTimeException: Zone offset hours not in valid range: value -20 is not in the range -18 to 18
        at java.base/java.time.ZoneOffset.ofHoursMinutes(ZoneOffset.java:...)
        at ezvcard.io.scribe.TimezoneScribe.parse(TimezoneScribe.java:355)
        at ezvcard.io.scribe.TimezoneScribe.parse(TimezoneScribe.java:281)
        at ezvcard.io.scribe.TimezoneScribe._parseText(TimezoneScribe.java:200)
        at ezvcard.io.text.VCardReader$VObjectDataListenerImpl.parseProperty(VCardReader.java:327)
        ...
        at ezvcard.io.chain.ChainingTextParser.all(ChainingTextParser.java:44)

**Cause.** `TimezoneScribe.parse(String)` (`src/main/java/ezvcard/io/scribe/TimezoneScribe.java`, the
private UTC-offset parser) documents `@throws IllegalArgumentException if the text cannot be parsed`, and
its callers (`_parseText`/`parse(String, VCardDataType, ...)`, lines ~270-290) rely on that: they catch
`IllegalArgumentException` and turn it into a `CannotParseException` (2.1) or a parse warning (3.0/4.0).
But the final step, `ZoneOffset.ofHoursMinutes(hour, minute)`, validates the range itself and throws
`java.time.DateTimeException` — a `RuntimeException` that is **not** an `IllegalArgumentException` — for
|hours| > 18 or |minutes| > 59. That exception is not caught and propagates out of the reader.

**Impact.** Any text vCard whose `TZ` (UTC-offset form) has an out-of-range hour or minute field makes
`Ezvcard.parse(...)` / `VCardReader.readNext()` throw an unchecked exception instead of recording the
documented parse warning. A service parsing untrusted vCards (address-book import, CardDAV sync) gets an
uncaught-exception failure for the whole import from a single malformed property — the exact failure
mode the lenient reader design is meant to prevent.

**One-line fix** (in `TimezoneScribe.parse(String)`):

    try { return ZoneOffset.ofHoursMinutes(hour, minute); }
    catch (java.time.DateTimeException e) { throw Messages.INSTANCE.getIllegalArgumentException(40, text); }

(or `catch (IllegalArgumentException | DateTimeException e)` at the two call sites).

Not a seed: reproducers here are replayed by nobody; `testsuite/` holds only valid inputs.
