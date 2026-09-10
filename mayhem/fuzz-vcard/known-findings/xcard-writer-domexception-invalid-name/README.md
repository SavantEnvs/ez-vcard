# XCardDocument: `org.w3c.dom.DOMException` when a parsed property name is not a legal XML name

**Found by:** `fuzz-vcard` (Jazzer) within ~100 execs from the committed seeds, when the harness still
round-tripped every parsed vCard through `Ezvcard.writeXml(...)`. The fuzzer mutated
`ANNIVERSARY:` into `ANNIVERSA$Y:` (see the `crash-...vcf` artifact). Because it is rediscovered on
practically every mutation of a property name, the xCard writer round-trip was **removed from the
harness** (mayhem/VCardFuzz.java) — keeping it would have made the campaign rediscover this one bug
forever instead of exploring the parsers. It remains a real upstream defect.

**Reproduce** (the shipped harness no longer calls `writeXml`; use the API directly):

    VCard v = Ezvcard.parse(Files.readString(Path.of("minimal-dollar-in-property-name.vcf"))).first();
    Ezvcard.writeXml(v).go();

    == Java Exception: org.w3c.dom.DOMException: INVALID_CHARACTER_ERR: An invalid or illegal XML character is specified.
        at java.xml/com.sun.org.apache.xerces.internal.dom.CoreDocumentImpl.checkQName(CoreDocumentImpl.java:2580)
        at java.xml/com.sun.org.apache.xerces.internal.dom.CoreDocumentImpl.createElementNS(CoreDocumentImpl.java:2097)
        at ezvcard.io.xml.XCardDocument$XCardDocumentStreamWriter.createElement(XCardDocument.java:763)
        at ezvcard.io.xml.XCardDocument$XCardDocumentStreamWriter.createElement(XCardDocument.java:772)
        at ezvcard.io.xml.XCardDocument$XCardDocumentStreamWriter.marshalProperty(XCardDocument.java:710)
        at ezvcard.io.xml.XCardDocument$XCardDocumentStreamWriter._write(XCardDocument.java:665)
        at ezvcard.io.chain.ChainingXmlWriter.go(ChainingXmlWriter.java:147)

**Cause.** The text reader (vinnie `SyntaxRules.vcard()`) accepts `$` and other non-XML-name characters
in property names, producing a `RawProperty` whose scribe (`RawPropertyScribe.getQName()`) uses the name
verbatim as the xCard element's local name. `XCardDocumentStreamWriter.marshalProperty`
(`src/main/java/ezvcard/io/xml/XCardDocument.java:710`) then calls `document.createElementNS(ns, name)`
with no validation, and the DOM implementation rejects the QName with an unchecked `DOMException`.
`marshalParameters` (line ~727) has the same shape for parameter names.

**Impact.** Converting an untrusted-but-parseable vCard to xCard (`Ezvcard.writeXml`, `XCardWriter`,
`XCardDocument.add`) throws an unchecked exception from a property that the library itself accepted
on input; a convert-to-XML service fails the whole document.

**One-line fix** (in `XCardDocumentStreamWriter.createElement(String name, String ns)`): validate the
name first and skip the property instead of handing an illegal QName to the DOM, e.g.

    if (!XMLChar.isValidNCName(name)) throw new SkipMeException();   // or map it to a safe x-name

(`com.sun.org.apache.xerces.internal.util.XMLChar.isValidNCName`, or any equivalent NCName check).
