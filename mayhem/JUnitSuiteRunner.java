// mayhem/JUnitSuiteRunner.java — runs the upstream JUnit 4 suite exactly as Maven Surefire selects
// it, without Maven at test time (test.sh is air-gapped and must not resolve plugins).
//
// Discovery mirrors Surefire's defaults + its JUnit4 provider: classes under the given
// target/test-classes matching **/Test*.class, **/*Test.class, **/*Tests.class, **/*TestCase.class,
// excluding inner classes, then keeping only public, concrete classes that carry @RunWith or at
// least one public @Test method. Runs them through JUnitCore with the text listener (dots +
// "OK (N tests)" / "Tests run: N,  Failures: F") and prints a machine-readable summary line
//     JUNIT classes=C tests=N failures=F ignored=I
// that mayhem/test.sh parses. Exit status 0 iff no failures.
import java.io.File;
import java.lang.reflect.Method;
import java.lang.reflect.Modifier;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

import org.junit.Test;
import org.junit.internal.TextListener;
import org.junit.runner.JUnitCore;
import org.junit.runner.Result;
import org.junit.runner.RunWith;
import org.junit.runner.notification.Failure;

public class JUnitSuiteRunner {
    public static void main(String[] args) throws Exception {
        File root = new File(args[0]);
        List<String> names = new ArrayList<>();
        collect(root, root, names);
        Collections.sort(names);
        List<Class<?>> classes = new ArrayList<>();
        for (String name : names) {
            Class<?> c = Class.forName(name, false, JUnitSuiteRunner.class.getClassLoader());
            int mods = c.getModifiers();
            if (!Modifier.isPublic(mods) || Modifier.isAbstract(mods) || c.isInterface()) continue;
            if (!c.isAnnotationPresent(RunWith.class) && !hasTestMethod(c)) continue;
            classes.add(c);
        }
        JUnitCore core = new JUnitCore();
        core.addListener(new TextListener(System.out));
        Result r = core.run(classes.toArray(new Class<?>[0]));
        for (Failure f : r.getFailures()) {
            System.out.println("FAILURE: " + f.getTestHeader());
            System.out.println(f.getTrace());
        }
        System.out.printf("JUNIT classes=%d tests=%d failures=%d ignored=%d%n",
            classes.size(), r.getRunCount(), r.getFailureCount(), r.getIgnoreCount());
        System.exit(r.wasSuccessful() ? 0 : 1);
    }

    private static boolean hasTestMethod(Class<?> c) {
        for (Method m : c.getMethods()) {
            if (m.isAnnotationPresent(Test.class)) return true;
        }
        return false;
    }

    private static void collect(File root, File dir, List<String> out) {
        File[] entries = dir.listFiles();
        if (entries == null) return;
        for (File f : entries) {
            if (f.isDirectory()) { collect(root, f, out); continue; }
            String n = f.getName();
            if (!n.endsWith(".class") || n.contains("$")) continue;
            String simple = n.substring(0, n.length() - ".class".length());
            if (!(simple.startsWith("Test") || simple.endsWith("Test") || simple.endsWith("Tests") || simple.endsWith("TestCase"))) continue;
            String rel = root.toURI().relativize(f.toURI()).getPath();
            out.add(rel.substring(0, rel.length() - ".class".length()).replace('/', '.'));
        }
    }
}
