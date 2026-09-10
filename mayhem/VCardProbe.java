// mayhem/VCardProbe.java — known-answer probe for mayhem/test.sh.
//
// Parses ONE fixed vCard file (argv[0]) with the same public API the fuzz target uses and prints
// KEY=VALUE lines that test.sh compares against exact expected values: the parsed fields, and the
// fields read back after re-serialising through every writer (text 3.0, jCard, xCard, hCard). A
// neutered / no-op library yields no lines (or wrong ones), so every assertion in test.sh fails.
import java.io.ByteArrayInputStream;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.util.List;

import ezvcard.Ezvcard;
import ezvcard.VCard;
import ezvcard.VCardVersion;
import ezvcard.property.Telephone;

public class VCardProbe {
    public static void main(String[] args) throws Exception {
        byte[] data = Files.readAllBytes(Paths.get(args[0]));
        List<VCard> vcards = Ezvcard.parse(new ByteArrayInputStream(data)).all();
        System.out.println("COUNT=" + vcards.size());
        VCard v = vcards.get(0);
        System.out.println("VERSION=" + v.getVersion().getVersion());
        System.out.println("FN=" + v.getFormattedName().getValue());
        System.out.println("N_FAMILY=" + v.getStructuredName().getFamily());
        System.out.println("N_GIVEN=" + v.getStructuredName().getGiven());
        System.out.println("N_SUFFIXES=" + String.join("|", v.getStructuredName().getSuffixes()));
        System.out.println("EMAIL=" + v.getEmails().get(0).getValue());
        System.out.println("EMAIL_TYPES=" + v.getEmails().get(0).getTypes());
        System.out.println("TEL_COUNT=" + v.getTelephoneNumbers().size());
        Telephone tel = v.getTelephoneNumbers().get(0);
        System.out.println("TEL_URI=" + (tel.getUri() == null ? tel.getText() : tel.getUri().toString()));
        System.out.println("ORG=" + v.getOrganization().getValues().get(0));
        System.out.println("GEO=" + v.getGeo().getLatitude() + "," + v.getGeo().getLongitude());
        System.out.println("LANG_COUNT=" + v.getLanguages().size());
        System.out.println("URL=" + v.getUrls().get(0).getValue());
        System.out.println("ADR_LOCALITY=" + v.getAddresses().get(0).getLocality());
        System.out.println("ADR_POSTAL=" + v.getAddresses().get(0).getPostalCode());
        System.out.println("BDAY=" + v.getBirthday().getPartialDate());
        System.out.println("VALIDATION_EMPTY=" + v.validate(v.getVersion()).isEmpty());

        // Round trips through every writer -> reader pair.
        String text3 = Ezvcard.write(v).version(VCardVersion.V3_0).go();
        VCard r3 = Ezvcard.parse(text3).first();
        System.out.println("RT_V3_VERSION=" + r3.getVersion().getVersion());
        System.out.println("RT_V3_FN=" + r3.getFormattedName().getValue());
        System.out.println("RT_V3_TEL_COUNT=" + r3.getTelephoneNumbers().size());

        String json = Ezvcard.writeJson(v).go();
        VCard rj = Ezvcard.parseJson(json).first();
        System.out.println("RT_JSON_STARTS=" + json.substring(0, 9));
        System.out.println("RT_JSON_EMAIL=" + rj.getEmails().get(0).getValue());
        System.out.println("RT_JSON_ORG=" + rj.getOrganization().getValues().get(0));

        String xml = Ezvcard.writeXml(v).go();
        VCard rx = Ezvcard.parseXml(xml).first();
        System.out.println("RT_XML_FN=" + rx.getFormattedName().getValue());
        System.out.println("RT_XML_N_FAMILY=" + rx.getStructuredName().getFamily());

        String html = Ezvcard.writeHtml(v).go();
        VCard rh = Ezvcard.parseHtml(html).first();
        System.out.println("RT_HTML_FN=" + rh.getFormattedName().getValue());
        System.out.println("RT_HTML_EMAIL=" + rh.getEmails().get(0).getValue());
    }
}
