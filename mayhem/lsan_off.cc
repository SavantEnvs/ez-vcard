// mayhem/lsan_off.cc — build-time LeakSanitizer off-switch (fleet policy, SPEC §6.2 item 15).
// Linked into every sanitizer-built ELF this port produces. ASan + UBSan stay fully active; only
// leak detection is disabled, and only through this link-time hook (never a runtime option).
extern "C" int __lsan_is_turned_off(void) { return 1; }
