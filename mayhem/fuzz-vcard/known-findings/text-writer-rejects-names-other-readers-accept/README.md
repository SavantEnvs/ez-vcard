# Text writer rejects property names / parameter values that the other readers accept

**Found by:** `fuzz-vcard` (Jazzer), ~2 000 execs from the seeds (a mutated `jcard-example.json`), then
narrowed with the hand-written inputs in this directory; a 150 s fork-mode campaign produced 11 more
artifacts, all of this class, in three message variants (two kept here as `crash-*`). Lower severity
than the two sibling findings: the exception is the **documented** behaviour of the text writer
(vinnie's `VObjectWriter.validate()` throws `IllegalArgumentException` for names/values that would break
vCard syntax), so the harness treats an `IllegalArgumentException` from the text-writer round-trip as
expected and lets every other exception propagate.

**Reproduce**

    /mayhem/fuzz-vcard-standalone j01-dot-name.json      # jCard property "x.y"           -> text writer IAE
    /mayhem/fuzz-vcard-standalone x01-dot-elem.xml       # xCard element <foo.bar>          -> text writer IAE
    /mayhem/fuzz-vcard-standalone h02-dot-class.html     # hCard class "x-foo.bar"          -> text writer IAE
    /mayhem/fuzz-vcard-standalone t08-quoted-param-nl.vcf# RFC 6868 ^n newline in a param   -> text writer IAE

(each is caught by the shipped harness; run `Ezvcard.write(Ezvcard.parseJson(...).first()).go()` etc. to
see it from the API)

    java.lang.IllegalArgumentException: Property name "x.y" contains one or more invalid characters.
      The following characters are not permitted: [ \n \r . : ; ]
    java.lang.IllegalArgumentException: Property "FOO" has a parameter named "X" whose value contains one
      or more invalid characters. ...
    java.lang.IllegalArgumentException: Property name cannot be empty.                     (crash-c913...)
    java.lang.IllegalArgumentException: Property name " Laurier, suite!!=0D=0ABEGIN" begins with one or
      more whitespace characters, which is not permitted.                                 (crash-986a...)
        at com.github.mangstadt.vinnie.io.VObjectWriter.validate(VObjectWriter.java:593/599)
        at com.github.mangstadt.vinnie.io.VObjectWriter.writeProperty(VObjectWriter.java:465)
        at ezvcard.io.text.VCardWriter._write(VCardWriter.java:340)
        at ezvcard.io.chain.ChainingTextWriter.go(ChainingTextWriter.java:251)

**Cause.** The jCard (`JCardRawReader`), xCard (`XCardReader`) and hCard (`HCardParser`) readers accept
any string as a property name (including empty and whitespace-led names), the text reader itself lets a
whitespace-led or otherwise odd property name through as a `RawProperty`, and it decodes RFC 6868 caret
escapes (`^n` -> newline) into parameter values; but `VCardWriter` (through vinnie's `VObjectWriter`) validates names/values against the
text syntax on write and throws. So a vCard produced by one of ez-vcard's own readers cannot be written
back as text.

**Impact.** Format conversion (jCard/xCard/hCard -> vCard text) on untrusted input fails with an unchecked
exception for the whole vCard; callers have no API to pre-validate. Enabling caret encoding
(`.caretEncoding(true)`) only covers the newline/quote case, not `.`, `:`, `;` in names.

**Fix (one line per reader, or one in the writer).** Either have the non-text readers reject/rename
illegal property names the way the text reader does (a `CannotParseException` + warning), or make
`VCardWriter` skip such properties with a warning instead of throwing — the asymmetry is the defect.
