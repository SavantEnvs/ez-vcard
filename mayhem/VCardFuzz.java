// mayhem/VCardFuzz.java — Jazzer harness for the `fuzz-vcard` target.
//
// Fuzzes ez-vcard's whole public parsing interface from raw bytes (no file I/O): the leading
// non-whitespace byte selects the encoding the same way real callers do —
//   '['               -> jCard  (RFC 7095 JSON)      Ezvcard.parseJson
//   "<?xml"/"<vcards" -> xCard  (RFC 6351 XML)       Ezvcard.parseXml   (XXE-hardened by ez-vcard)
//   other '<'         -> hCard  (HTML microformat)   Ezvcard.parseHtml
//   anything else     -> vCard  2.1 / 3.0 / 4.0 text Ezvcard.parse
// so the committed seeds stay plain, valid vCards in each encoding. Every parsed vCard is then
// validated against its own version and re-serialised to jCard and text, which exercises the
// scribes' write paths on fuzzer-shaped property values (the text writer's documented
// IllegalArgumentException for unserialisable names/values is the one expected exception there).
//
// The xCard (XML) writer is deliberately NOT round-tripped: it throws an unchecked
// org.w3c.dom.DOMException on any parsed property whose name is not a legal XML name (found within
// ~100 execs from the seeds; recorded with a reproducer under
// mayhem/fuzz-vcard/known-findings/xcard-writer-domexception-invalid-name/) — keeping it in would
// make the campaign rediscover that one bug forever instead of exploring the parsers.
//
// Parsers reject malformed input with a checked IOException (SAX/JSON parse errors arrive wrapped in
// it) — expected and swallowed; any unchecked exception (NPE, IndexOutOfBounds, NumberFormat,
// DateTimeException, StackOverflow, ...) surfaces as a Jazzer finding.
import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.util.List;

import ezvcard.Ezvcard;
import ezvcard.VCard;
import ezvcard.VCardVersion;

public class VCardFuzz {
    public static void fuzzerTestOneInput(byte[] data) {
        int i = 0;
        while (i < data.length && (data[i] == ' ' || data[i] == '\t' || data[i] == '\r' || data[i] == '\n')) i++;
        List<VCard> vcards;
        try {
            if (i < data.length && data[i] == '[') {
                vcards = Ezvcard.parseJson(new ByteArrayInputStream(data)).all();
            } else if (i < data.length && data[i] == '<') {
                if (startsWith(data, i, "<?xml") || startsWith(data, i, "<vcards")) {
                    vcards = Ezvcard.parseXml(new ByteArrayInputStream(data)).all();
                } else {
                    vcards = Ezvcard.parseHtml(new ByteArrayInputStream(data)).all();
                }
            } else {
                vcards = Ezvcard.parse(new ByteArrayInputStream(data)).all();
            }
        } catch (IOException e) {
            return; // malformed input, rejected the documented way (SAX/JSON errors arrive wrapped as IOException)
        }
        for (VCard vcard : vcards) {
            VCardVersion version = vcard.getVersion() == null ? VCardVersion.V4_0 : vcard.getVersion();
            vcard.validate(version);
            Ezvcard.writeJson(vcard).go();
            try {
                Ezvcard.write(vcard).version(version).go();
            } catch (IllegalArgumentException e) {
                // Documented contract, not a crash: IllegalArgumentException is the text writer's declared
                // rejection of content it cannot serialise — vinnie's VObjectWriter.validate() throws it
                // for property/parameter names that are empty, start with whitespace or contain
                // characters illegal in vCard syntax, and for parameter values it cannot encode — and the
                // jCard/xCard/hCard readers (and RFC 6868 caret decoding) accept exactly such content.
                // See mayhem/fuzz-vcard/known-findings/text-writer-rejects-names-other-readers-accept/.
                // Every other unchecked exception from the writer still propagates as a finding.
            }
        }
    }

    private static boolean startsWith(byte[] data, int off, String prefix) {
        if (data.length - off < prefix.length()) return false;
        for (int k = 0; k < prefix.length(); k++) {
            if (data[off + k] != (byte) prefix.charAt(k)) return false;
        }
        return true;
    }
}
